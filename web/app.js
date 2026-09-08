/* =====================================================================
   FPGA Robot Digital Twin - control console
   ------------------------------------------------------------
   Layers (data flows down, nothing random):
     SerialManager  /  DemoSimulator   ->  TelemetryParser / demo model
              ->  robotState (single source of truth)
              ->  rAF render loop -> SVG robot + DOM readouts
              ->  pushSample -> time-series -> Canvas charts
   Protocol (confirmed from rtl/uart_telemetry.v + top_system.v):
     frame = [0xAA][state][target][pos][chk], 5 bytes
     state byte = {5'd0, fsm_state} -> 0..4
     chk  = 0xAA ^ state ^ target ^ pos
     target / pos are the low 8 bits of the 10-bit 0..180 values
     cadence TELEM_MS=100 -> about 10 Hz @ 115200 8N1
   ===================================================================== */
'use strict';

/* ---------------- Protocol constants (from RTL) ---------------- */
const PROTO = {
  HEAD: 0xAA,
  FRAME_LEN: 5,
  BAUD: 115200,
  // state machine localparams in rtl/state_machine.v (3'd0..3'd4)
  STATES: ['IDLE', 'READY', 'MOVE', 'HOLD', 'FAULT'],
};

/* ---------------- small helpers ---------------- */
const $ = (id) => document.getElementById(id);
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

function timeStr(ts) {
  const d = ts ? new Date(ts) : new Date();
  const p = (n) => String(n).padStart(2, '0');
  return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}

/* =====================================================================
   TelemetryParser - robust streaming frame parser.
   Handles partial frames, several frames in one read, frames split
   across reads, garbage bytes and checksum errors (self re-syncing).
   ===================================================================== */
class TelemetryParser {
  constructor(onFrame, stats) {
    this._onFrame = onFrame;       // onFrame({state,target,pos,time})
    this._stats = stats || { rxBytes: 0, valid: 0, invalid: 0, checksumErr: 0 };
    this._buf = [];                // sliding byte buffer
    this._t = Date.now();          // last-frame time, updated by emit
    this._times = [];              // recent valid-frame timestamps (for rate)
  }

  resetCounters() {
    this._stats.rxBytes = 0; this._stats.valid = 0;
    this._stats.invalid = 0; this._stats.checksumErr = 0;
    this._times = [];
  }

  // average valid frame frequency over the last 3 s (Hz)
  rateHz() {
    const now = Date.now();
    const cutoff = now - 3000;
    while (this._times.length && this._times[0] < cutoff) this._times.shift();
    return this._times.length / 3;
  }

  push(chunk) {
    // accept Uint8Array / Array / number
    const src = (chunk instanceof Uint8Array) ? chunk
              : (typeof chunk === 'number') ? new Uint8Array([chunk]) : new Uint8Array(chunk);
    for (const b of src) {
      this._buf.push(b);
      this._stats.rxBytes++;
    }

    let i = 0;
    const L = this._buf.length;
    while (i + (PROTO.FRAME_LEN - 1) < L) {
      if (this._buf[i] === PROTO.HEAD) {
        const st = this._buf[i + 1];
        const tg = this._buf[i + 2];
        const po = this._buf[i + 3];
        const ck = this._buf[i + 4];
        if (ck === (PROTO.HEAD ^ st ^ tg ^ po)) {
          this._stats.valid++;
          const now = Date.now();
          this._t = now;
          this._times.push(now);
          if (this._times.length > 120) this._times.shift();
          this._onFrame({ state: st, target: tg, pos: po, chk: ck });
          i += PROTO.FRAME_LEN;           // consume the whole valid frame
          continue;
        } else {
          this._stats.checksumErr++;
          this._stats.invalid++;
          i += 1;                          // header was noise -> resync byte-by-byte
          continue;
        }
      }
      i += 1;
    }
    if (i > 0) this._buf.splice(0, i);     // drop consumed bytes
  }
}

/* =====================================================================
   SerialManager - Web Serial API wrapper (Chrome / Edge only).
   ===================================================================== */
class SerialManager {
  constructor(opts) {
    this.onData = opts.onData || (() => {});
    this.onOpen = opts.onOpen || (() => {});
    this.onClose = opts.onClose || (() => {});
    this._port = null;
    this._reader = null;
    this._reading = false;
  }
  supported() { return !!navigator.serial; }

  async connect() {
    if (!this.supported()) throw new Error('WS_UNSUPPORTED');
    // browsers keep a per-origin list; forget old ports not needed.
    const port = await navigator.serial.requestPort();
    await port.open({ baudRate: PROTO.BAUD });
    this._port = port;
    this._reading = true;
    this._readLoop().catch((e) => this._handleReadEnd(e));
    // read a couple of port attributes for the UI
    const info = port.getInfo ? port.getInfo() : {};
    return { port, usb: info.usbVendorId !== undefined };
  }

  async _readLoop() {
    const port = this._port;
    while (this._reading && port && port.readable) {
      const reader = port.readable.getReader();
      this._reader = reader;
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          if (value && value.length) this.onData(value);
        }
      } finally {
        reader.releaseLock();
      }
      this._reader = null;
      if (!this._reading) break;
      await new Promise((r) => setTimeout(r, 50)); // transient; allow reopen
    }
  }

  _handleReadEnd(err) {
    this._reading = false;
    if (err && err.name !== 'AbortError') {
      // unexpected loss (USB unplugged etc.)
    }
    this.onClose(err);
  }

  async disconnect() {
    this._reading = false;
    try { if (this._reader) await this._reader.cancel(); } catch (_) {}
    try { if (this._reader) this._reader.releaseLock(); } catch (_) {}
    try { if (this._port) await this._port.close(); } catch (_) {}
    this._port = null; this._reader = null;
  }
  get portInfo() { return this._port ? this._port.getInfo() : null; }
}

/* =====================================================================
   DemoSimulator - mirrors rtl behaviour WITHOUT any hardware:
     target input -> trajectory (VEL deg/s) -> P-feedback command
     -> 1st-order virtual motor (TAU) -> position.
   Parameters copied from top_system.v / virtual_motor.v / pid_controller.v:
     VEL_DEG_S = 150, KP = 2 deg/s per deg, VMAX = 60 deg/s, TAU = 100 ms.
   ===================================================================== */
class DemoSimulator {
  constructor() {
    this.VEL = 150;      // reference ramp speed deg/s (trajectory)
    this.KP = 2;         // cmd [deg/s] = KP * err  (pid KP_EFF/2^PID_SH -> ~2)
    this.VMAX = 60;      // motor max speed deg/s
    this.TAU = 100;      // motor 1st-order time constant ms
    this.TOL = 2;        // |target - pos| <= TOL -> HOLD (at_target in top_system)
    this.reset();
  }
  reset() {
    this.pos = 0; this.vel = 0; this.ref = 0;
    this.target = 0; this.targetValid = false; this.moving = false;
    this.fault = false; this.state = 0;        // IDLE
    this._prevState = 0;
  }
  /* API used by controller */
  start(targetDeg) {
    if (this.fault) return false;               // must ACK first, like RTL
    this.target = clamp(targetDeg, 0, 180);
    this.targetValid = true;
    this.ref = this.pos;                         // trajectory starts from current pos
    this.moving = true;
    this._setState(2);                           // MOVE
    return true;
  }
  stop() {
    if (this.fault) return;
    this.moving = false; this.ref = this.pos;    // freeze where it is
    this._setState(this.targetValid ? 1 : 0);    // READY if a target is set else IDLE
  }
  clear() {
    if (this.fault) { this.fault = false; this.vel = 0; this._setState(0); this.targetValid = false; return; }
    this.moving = false; this.targetValid = false; this.ref = this.pos;
    this._setState(0);
  }
  faultForDemo() {                               // demo-only manual fault
    this.fault = true; this.vel = 0; this.moving = false;
    this._setState(4);
  }
  /* run one physics tick of `ms` milliseconds */
  step(ms) {
    if (this.fault) { this.vel = 0; return; }
    const DT = ms / 1000;
    if (this.moving) {
      const diff = this.target - this.ref;
      const stepMax = this.VEL * DT;
      if (Math.abs(diff) <= stepMax) this.ref = this.target;
      else this.ref += Math.sign(diff) * stepMax;
    }
    let cmd = clamp(this.KP * (this.ref - this.pos), -this.VMAX, this.VMAX);
    this.vel += (cmd - this.vel) * (ms / this.TAU);
    this.vel = clamp(this.vel, -this.VMAX, this.VMAX);
    if (this.pos >= 180 && this.vel > 0) this.vel = 0;   // joint stops at ends
    if (this.pos <= 0   && this.vel < 0) this.vel = 0;
    this.pos = clamp(this.pos + this.vel * DT, 0, 180);

    if (this.state === 2) {                                // MOVE
      if (Math.abs(this.target - this.pos) <= this.TOL) {
        this.moving = false;
        this._setState(3);                                 // HOLD
      }
    }
  }
  _setState(s) {
    this.state = s;
    if (s !== this._prevState) {
      this._prevState = s;
      if (this.onStateChange) this.onStateChange(s);
    }
  }
}

/* =====================================================================
   TwinChart - a small rolling-window canvas line chart (no library).
   ===================================================================== */
const SERIES_COLOR = { target: '#37d5ff', actual: '#43e28b', err: '#ffc05c', vel: '#b98cff' };

class TwinChart {
  constructor(canvas, seriesList, opts = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.series = seriesList.map((s) => ({ key: s.key, color: SERIES_COLOR[s.key] || s.color }));
    this.fixed = opts.fixed;          // [min,max] or null for auto
    this.zeroCenter = !!opts.zeroCenter;
    this.unit = opts.unit || '';
    this.window = opts.window || 15;  // seconds shown
    this.hist = [];                   // {t, [key]:value}
    this.maxPts = 1500;               // memory cap
    this._dpr = 1;
    this._resize = this._resize.bind(this);
    this._resize();
    if (typeof ResizeObserver !== 'undefined') new ResizeObserver(this._resize).observe(canvas);
  }
  _resize() {
    const cssW = this.canvas.clientWidth || 300;
    const cssH = this.canvas.clientHeight || 150;
    this._dpr = window.devicePixelRatio || 1;
    this.canvas.width = Math.round(cssW * this._dpr);
    this.canvas.height = Math.round(cssH * this._dpr);
    this.draw();
  }
  push(t, vals) {
    this.hist.push(Object.assign({ t }, vals));
    if (this.hist.length > this.maxPts) this.hist.shift();
  }
  clear() { this.hist = []; this.draw(); }

  draw() {
    const ctx = this.ctx, W = this.canvas.width, H = this.canvas.height;
    if (!W) return;
    ctx.clearRect(0, 0, W, H);
    const padL = 34 * this._dpr, padR = 8 * this._dpr, padT = 6 * this._dpr, padB = 18 * this._dpr;
    const pw = W - padL - padR, ph = H - padT - padB;
    if (ph <= 0) return;
    const data = this.hist;
    const tMax = data.length ? data[data.length - 1].t : 0;
    const t0 = tMax - this.window;

    // ---- y domain ----
    let ymin, ymax;
    if (this.fixed) { ymin = this.fixed[0]; ymax = this.fixed[1]; }
    else {
      ymin = Infinity; ymax = -Infinity;
      for (const p of data) for (const s of this.series) {
        const v = p[s.key]; if (v === null || v === undefined) continue;
        if (v < ymin) ymin = v; if (v > ymax) ymax = v;
      }
      if (!isFinite(ymin)) { ymin = this.zeroCenter ? -1 : 0; ymax = 1; }
      const m = (ymax - ymin) * 0.1 + 1e-6;
      ymin -= m; ymax += m;
      if (this.zeroCenter) { const m2 = Math.max(Math.abs(ymin), Math.abs(ymax)); ymin = -m2; ymax = m2; }
    }
    const span = (ymax - ymin) || 1;
    const X = (t) => padL + ((t - t0) / this.window) * pw;
    const Y = (v) => padT + ph - ((v - ymin) / span) * ph;

    // ---- grid + y labels ----
    ctx.font = (10 * this._dpr) + 'px "Cascadia Mono", monospace';
    ctx.textBaseline = 'middle';
    ctx.strokeStyle = 'rgba(120,140,158,0.14)';
    ctx.lineWidth = 1;
    const steps = 4;
    for (let k = 0; k <= steps; k++) {
      const v = ymin + (span * k) / steps;
      const y = Y(v);
      ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(W - padR, y); ctx.stroke();
      ctx.fillStyle = 'rgba(122,138,158,0.8)';
      ctx.textAlign = 'right';
      ctx.fillText(v.toFixed(this.unit === 'deg' && Math.abs(v) < 200 ? 0 : 0), padL - 4 * this._dpr, y);
    }
    // time labels (right-aligned seconds ago)
    ctx.textAlign = 'left';
    for (let s = 0; s <= this.window; s += Math.max(5, Math.round(this.window / 3))) {
      const x = X(tMax - s);
      if (x < padL - 2 || x > W - padR + 2) continue;
      ctx.fillStyle = 'rgba(122,138,158,0.55)';
      ctx.fillText('-' + s + 's', x, H - 4 * this._dpr);
    }
    // y = 0 axis emphasis for err/vel
    if (ymin < 0 && ymax > 0) {
      ctx.strokeStyle = 'rgba(255,192,92,0.25)';
      ctx.beginPath(); ctx.moveTo(padL, Y(0)); ctx.lineTo(W - padR, Y(0)); ctx.stroke();
    }

    // ---- clip + plot ----
    ctx.save();
    ctx.beginPath(); ctx.rect(padL, padT, pw, ph); ctx.clip();
    for (const s of this.series) {
      ctx.strokeStyle = s.color;
      ctx.lineWidth = 1.6 * this._dpr;
      ctx.beginPath();
      let pen = false;
      for (const p of data) {
        const v = p[s.key];
        if (v === null || v === undefined) { pen = false; continue; }
        const x = X(p.t), y = Y(v);
        if (!pen) { ctx.moveTo(x, y); pen = true; } else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
    ctx.restore();
  }
}

/* =====================================================================
   DigitalTwin SVG - wall_e.png as the virtual robot body (static image,
   never distorted).  The pose is conveyed by the surrounding markers:
     · dashed cyan ring segment + small target puck  -> commanded target
     · solid green arc (history trail)               -> actual position
     · current "angle needle" that the robot points at -> actual angle
   Angle convention: 0 = UP (needle vertical), +90 = RIGHT, 180 = DOWN.
   ===================================================================== */
const Twin = (() => {
  const W = 460, H = 320;
  const PX = W / 2, PY = H / 2;              // robot centre (pivot)
  const R_OUT = 128;                          // outer pointer radius
  const ROBOT_W = 104, ROBOT_H = 104;         // robot sprite size (px, keeps aspect)
  const pt = (deg, r = R_OUT) => ({
    x: PX + r * Math.sin(deg * Math.PI / 180),
    y: PY - r * Math.cos(deg * Math.PI / 180),
  });
  // big arc 0..180 used for scale + target ring, drawn clockwise on the right
  const arcD = (() => {
    const p0 = pt(0), p1 = pt(180);
    return `M ${p0.x.toFixed(1)} ${p0.y.toFixed(1)} A ${R_OUT} ${R_OUT} 0 0 1 ${p1.x.toFixed(1)} ${p1.y.toFixed(1)}`;
  })();

  let gTgt, gAct, hubGlowEl, tailLayer, tagTarget, tagActual, robotImg, targetArc, targetPuck;
  let dotEls = [], tailPts = [], _lastTailDeg = null;

  function build() {
    const host = $('robotCanvas');
    let ticks = '';
    for (let d = 0; d <= 180; d += 15) {
      const a = pt(d, R_OUT), b = pt(d, R_OUT + 8);
      ticks += `<line x1="${a.x.toFixed(1)}" y1="${a.y.toFixed(1)}" x2="${b.x.toFixed(1)}" y2="${b.y.toFixed(1)}" stroke="rgba(130,150,170,.45)" stroke-width="1"/>`;
      if (d % 45 === 0) {
        const lb = pt(d, R_OUT + 20);
        ticks += `<text x="${lb.x.toFixed(1)}" y="${(lb.y + 4).toFixed(1)}" text-anchor="middle"
                   font-size="11" fill="rgba(140,160,180,.75)" font-family="Cascadia Mono,monospace">${d}&deg;</text>`;
      }
    }

    host.innerHTML = `
    <svg viewBox="0 0 ${W} ${H}" width="100%" height="100%" preserveAspectRatio="xMidYMid meet"
         role="img" aria-label="virtual robot twin">
      <defs>
        <radialGradient id="glowGrad" cx="50%" cy="50%" r="50%">
          <stop offset="0%"  stop-color="rgba(55,213,255,.18)"/>
          <stop offset="60%" stop-color="rgba(55,213,255,.05)"/>
          <stop offset="100%" stop-color="rgba(55,213,255,0)"/>
        </radialGradient>
      </defs>

      <!-- scale arc + ticks -->
      <circle cx="${PX}" cy="${PY}" r="${R_OUT}" fill="none" stroke="rgba(60,80,100,.16)" stroke-dasharray="2 6"/>
      <path d="${arcD}" fill="none" stroke="rgba(55,213,255,.22)" stroke-width="1.3"/>
      ${ticks}

      <!-- actual-position history trail (green) -->
      <g id="tailLayer"></g>

      <!-- soft glow behind the robot -->
      <ellipse cx="${PX}" cy="${PY}" rx="${ROBOT_W * 0.62}" ry="${ROBOT_H * 0.62}" fill="url(#glowGrad)"/>

      <!-- actual position pointer (a clean needle, no arm) -->
      <g id="actArm">
        <line x1="${PX}" y1="${PY}" x2="${PX}" y2="${PY - R_OUT}"
              stroke="rgba(67,226,139,.95)" stroke-width="3" stroke-linecap="round"/>
        <circle cx="${PX}" cy="${PY - R_OUT}" r="6" fill="#0a0e14" stroke="#43e28b" stroke-width="2.4"/>
      </g>
      <text id="actTag" font-size="11" fill="#43e28b" font-family="Cascadia Mono,monospace"
            text-anchor="middle" font-weight="bold"></text>

      <!-- target: dashed cyan ring segment + small puck -->
      <path id="targetArc" d="" fill="none" stroke="rgba(55,213,255,.95)" stroke-width="4" stroke-linecap="round" stroke-dasharray="10 5"/>
      <circle id="targetPuck" cx="${PX}" cy="${PY - R_OUT}" r="7" fill="#0a0e14" stroke="#37d5ff" stroke-width="2.5"/>
      <text id="tgtTag" font-size="11" fill="#37d5ff" font-family="Cascadia Mono,monospace"
            text-anchor="middle" font-weight="bold"></text>

      <!-- the robot: your wall_e.png, centered, never stretched -->
      <g id="robotBody">
        <image id="robotImg" href="wall_e.png"
               x="${PX - ROBOT_W / 2}" y="${PY - ROBOT_H / 2}"
               width="${ROBOT_W}" height="${ROBOT_H}"
               preserveAspectRatio="xMidYMid meet" crossorigin="anonymous"/>
        <circle id="hubGlow" cx="${PX}" cy="${PY}" r="4" fill="#43e28b"/>
      </g>
    </svg>`;

    gTgt = null;
    gAct = host.querySelector('#actArm');
    hubGlowEl = host.querySelector('#hubGlow');
    tailLayer = host.querySelector('#tailLayer');
    tagTarget = host.querySelector('#tgtTag');
    tagActual = host.querySelector('#actTag');
    robotImg = host.querySelector('#robotImg');
    targetArc = host.querySelector('#targetArc');
    targetPuck = host.querySelector('#targetPuck');
    _makeTailDots();
  }

  function _makeTailDots() {
    const frag = document.createDocumentFragment();
    for (let i = 0; i < 140; i++) {
      const c = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      c.setAttribute('r', 2.4);
      c.setAttribute('fill', '#43e28b');
      dotEls.push(c);
      frag.appendChild(c);
    }
    tailLayer.appendChild(frag);
  }

  function updateTail(deg) {
    if (_lastTailDeg !== null && Math.abs(deg - _lastTailDeg) < 1.2) return;
    _lastTailDeg = deg;
    const p = pt(deg, R_OUT - 2);
    tailPts.push({ x: p.x, y: p.y });
    if (tailPts.length > 120) tailPts.shift();
    renderTail();
  }
  function renderTail() {
    const n = tailPts.length;
    for (let i = 0; i < dotEls.length; i++) {
      const el = dotEls[i];
      if (i < n) {
        const p = tailPts[i];
        el.setAttribute('cx', p.x);
        el.setAttribute('cy', p.y);
        el.style.opacity = (0.08 + 0.35 * (i / n)).toFixed(3);
        el.style.display = '';
      } else el.style.display = 'none';
    }
  }

  // arc from the 0 mark to `deg` along the outer circle (for target)
  function arcTo(deg) {
    deg = Math.max(0, Math.min(180, deg));
    const p0 = pt(0), p1 = pt(deg);
    const largeArc = (deg > 180) ? 1 : 0;
    return `M ${p0.x.toFixed(1)} ${p0.y.toFixed(1)} A ${R_OUT} ${R_OUT} 0 ${largeArc} 1 ${p1.x.toFixed(1)} ${p1.y.toFixed(1)}`;
  }

  function draw(actualDeg, targetDeg, faulted) {
    const aN = (actualDeg === null || actualDeg === undefined);
    const tN = (targetDeg === null || targetDeg === undefined);
    const aD = aN ? 0 : actualDeg;
    const tD = tN ? 0 : targetDeg;
    // pointer + tags
    gAct.setAttribute('transform', `rotate(${aD} ${PX} ${PY})`);
    targetArc.setAttribute('d', arcTo(tD));
    const tp = pt(tD, R_OUT);
    targetPuck.setAttribute('cx', tp.x); targetPuck.setAttribute('cy', tp.y);

    const ta = pt(aD, R_OUT + 14);
    const tg = pt(tD, R_OUT + 14);
    tagActual.setAttribute('x', ta.x); tagActual.setAttribute('y', ta.y + 4);
    tagTarget.setAttribute('x', tg.x); tagTarget.setAttribute('y', tg.y + 4);
    tagActual.textContent = aN ? '—' : Math.round(actualDeg);
    tagTarget.textContent = tN ? '—' : Math.round(targetDeg);

    // robot: do NOT rotate the image (keeps it clean); fault shown by glow + glow colour
    if (faulted) {
      hubGlowEl.setAttribute('fill', '#ff5c63');
      robotImg.style.filter = 'saturate(1.15) drop-shadow(0 0 10px rgba(255,92,99,.9))';
    } else {
      hubGlowEl.setAttribute('fill', '#43e28b');
      robotImg.style.filter = '';
    }
  }
  return { build, draw, updateTail, clearTail() { _lastTailDeg = null; tailPts = []; renderTail(); } };
})();

/* =====================================================================
   App controller - glues everything together.
   ===================================================================== */
const Controller = {
  state: {
    mode: 'DEMO',          // 'DEMO' | 'LIVE'
    connected: false,      // Web Serial open
    linkErr: null,
    stateIdx: 0,           // current FSM state 0..4
    target: 0,
    position: 0,           // most recent telemetry / model value (int-ish)
    velocity: null,        // deg/s ; LIVE = estimate, DEMO = model
    velSrc: '',
    lastFrameMs: 0,
    commTimeout: false,
    rate: 0,
  },

  livePts: [],             // [{t,pos}] last few LIVE frames for interpolation
  tailAcc: 0,

  init() {
    this.parserStats = { rxBytes: 0, valid: 0, invalid: 0, checksumErr: 0 };
    this.parser = new TelemetryParser((f) => this.onTelemetry(f), this.parserStats);
    this.serial = new SerialManager({
      onData: (d) => this.parser.push(d),
      onOpen: () => {},
      onClose: () => this.onLinkLost(),
    });
    this.demo = new DemoSimulator();
    this.demo.onStateChange = (s) => {
      if (this.state.mode !== 'DEMO') return;
      this.state.stateIdx = s;
      this.log('STATE → ' + PROTO.STATES[s], s === 4 ? 'err' : 'info');
      if (s === 4) this.log('ROBOT FAULT · safe-stop', 'err');
    };

    this.t0 = Date.now();
    Twin.build();
    this.bindUI();
    this.buildStateFlow();

    // charts
    this.chPos = new TwinChart($('chartPos'), [{ key: 'target' }, { key: 'actual' }], { fixed: [-5, 185], unit: 'deg', window: 15 });
    this.chErr = new TwinChart($('chartErr'), [{ key: 'err' }], { unit: 'deg', zeroCenter: true, window: 15 });
    this.chVel = new TwinChart($('chartVel'), [{ key: 'vel' }], { unit: 'deg/s', zeroCenter: true, window: 15 });

    this._lastSample = 0;
    this._acc = 0;             // demo simulation accumulator
    this._lastMode = this.state.mode;

    // start render loop
    this._lastFrameNow = performance.now();
    requestAnimationFrame(this._tick.bind(this));

    this.setMode('DEMO');
    this.setLinkUI(false);
    this.updateSourceUI();

    // make a few internals reachable for console self-tests / debugging
    window.__twin = {
      parser: this.parser,
      demo: this.demo,
      ctrl: this,
      PROTO,
      runSelfTests,
      // feed raw bytes into the same parser used by Web Serial (for tests)
      feedLive: (b) => this.parser.push(b),
      // re-run a preset demo experiment (1..4)
      exp: (n) => { if (this.state.mode === 'DEMO') this.startExperiment(n); },
      // demo-only fault injection
      faultDemo: () => {
        if (this.state.mode === 'DEMO') {
          this.demo.faultForDemo();
          this.state.stateIdx = 4;
          this.log('FAULT INJECTED (demo)', 'err');
        }
      },
    };

    if (new URLSearchParams(location.search).get('selftest') !== null) {
      setTimeout(() => { const r = runSelfTests(); this.log('SELF-TEST ' + (r.ok ? 'PASS' : 'FAIL') + ' (' + r.pass + '/' + r.total + ')', r.ok ? 'ok' : 'err'); }, 400);
    }
    // gentle auto demo so the page is alive immediately
    this.demoAutoTimer = setTimeout(() => { if (this.state.mode === 'DEMO') this.startExperiment(1); }, 900);
  },

  demoAutoStop() {
    if (this.demoAutoTimer) { clearTimeout(this.demoAutoTimer); this.demoAutoTimer = null; }
  },

  /* ---------- source & telemetry ---------- */
  setMode(m) {
    this.state.mode = m;
    const badge = $('modeBadge');
    badge.textContent = (m === 'LIVE') ? 'LIVE FPGA' : 'DEMO';
    badge.className = 'mode-badge ' + (m === 'LIVE' ? 'live' : 'demo');
    // switching data source: drop the previous mode's history & pose so the old
    // DEMO target (e.g. auto-run Exp1 = 90) can never mix into the LIVE view.
    this._clearCharts();
    if (m === 'LIVE') {
      // entering LIVE: nothing is known until the first real frame arrives.
      this.state.velocity = null;
      this.state.velSrc = '';
      this.state.target = null;
      this.state.position = null;
      this.livePts = [];
      this._frameHist = [];
      this._updateFrameLog();
      Twin.clearTail();
      this._lastDisp = undefined;
    } else {
      this.state.velocity = this.demo.vel;
      this.state.velSrc = 'model';
    }
    this._hudSnap = null;          // force a redraw on the next tick
    this.updateControlUI();
    this.updateSourceUI();
    this.updateStateFlow();
  },

  _clearCharts() {
    if (!this.chPos) return;
    this.chPos.clear(); this.chErr.clear(); this.chVel.clear();
  },

  onTelemetry(f) {
    if (f.state > 4) return;                 // unknown -> ignore
    this.state.stateIdx = f.state;
    this.state.target = f.target;
    this.state.position = f.pos;
    this.state.lastFrameMs = Date.now();
    this.state.commTimeout = false;
    this._firstWarn = false;
    // raw-frame history (helps spot oscillation / framing on real hardware)
    if (!this._frameHist) this._frameHist = [];
    this._frameHist.push({ state: f.state, target: f.target, pos: f.pos, chk: f.chk });
    if (this._frameHist.length > 12) this._frameHist.shift();
    this._updateFrameLog();
    if (this.state.mode === 'LIVE') {
      // estimate velocity from consecutive frames
      const now = Date.now();
      this.livePts.push({ t: now, pos: f.pos });
      if (this.livePts.length > 2) this.livePts.shift();
      if (this.livePts.length === 2) {
        const [a, b] = this.livePts;
        const dt = (b.t - a.t) / 1000;
        if (dt > 0.01) {
          const v = (b.pos - a.pos) / dt;
          const alpha = 0.35;
          this.state.velocity = (this.state.velocity === null) ? v
            : alpha * v + (1 - alpha) * this.state.velocity;
          this.state.velSrc = 'est';
        }
      }
    }
    this.pushSample();
    this._render();
  },

  onLinkLost() {
    if (!this.state.connected) return;
    this.log('FPGA DISCONNECTED (link lost)', 'warn');
    this.leaveLive('LINK LOST');
  },

  leaveLive(reason) {
    this.state.connected = false;
    this.state.linkErr = reason || null;
    this.state.commTimeout = false;
    this.livePts = [];
    this.setLinkUI(false);
    this.setMode('DEMO');
    // keep last known pose as demo starting pose to avoid a visual jump
    this.demo.reset();
    this.demo.pos = clamp(this.state.position, 0, 180);
    this.demo.ref = this.demo.pos;
    this.log('MODE → DEMO (' + (reason || 'switched') + ')', 'info');
  },

  async connectLive() {
    if (!navigator.serial) {
      this.state.linkErr = 'Web Serial is not supported in this browser. Please use Chrome or Edge.';
      this.showWsError(this.state.linkErr);
      this.log('WEB SERIAL UNSUPPORTED', 'err');
      return;
    }
    try {
      const r = await this.serial.connect();
      this.state.connected = true;
      this.state.linkErr = null;
      this._connectAt = Date.now();
      this._firstWarn = false;
      this.hideWsError();
      this.demoAutoStop();
      this.setMode('LIVE');
      this.setLinkUI(true);
      this.parserStats.rxBytes = this.parserStats.valid = this.parserStats.invalid = this.parserStats.checksumErr = 0;
      const info = this.serial.portInfo;
      const label = (info && info.usbVendorId) ? ('USB ' + info.usbVendorId.toString(16) + ':' + info.usbProductId.toString(16)) : 'n/a';
      $('linkPort').textContent = label;
      this.log('FPGA CONNECTED · ' + label + ' @ ' + PROTO.BAUD, 'ok');
      this.state.lastFrameMs = 0;
      this.updateControlUI();
      this.updateSourceUI();
      return true;
    } catch (err) {
      if (err && err.name === 'NotFoundError') { this.log('Connection cancelled', 'dim'); return; }
      const msg = (err && err.message) ? err.message : 'Cannot open serial port';
      this.state.linkErr = msg;
      this.log('CONNECT FAILED · ' + msg, 'err');
    }
  },

  async disconnectLive() {
    try { await this.serial.disconnect(); } catch (_) {}
    this.leaveLive('user disconnect');
    this.log('FPGA DISCONNECTED', 'warn');
  },

  /* ---------- samples -> charts ---------- */
  pushSample() {
    const t = (Date.now() - this.t0) / 1000;
    const v = this.state.velocity;
    this.chPos.push(t, { target: this.state.target, actual: this.state.position });
    this.chErr.push(t, { err: this.state.target - this.state.position });
    this.chVel.push(t, { vel: (v === null || this.state.velSrc === '') ? null : Math.round(v * 10) / 10 });
    // charts are small: redraw on every new sample (about 10 Hz)
    this.chPos.draw();
    this.chErr.draw();
    this.chVel.draw();
  },

  /* raw frame history -> FPGA LINK debug panel */
  _updateFrameLog() {
    const el = $('frameLog');
    if (!el) return;
    const hx = (n) => ('0' + (n & 0xff).toString(16).toUpperCase()).slice(-2);
    const st = (n) => PROTO.STATES[n] || ('?' + n);
    const rows = this._frameHist.map((f) => {
      const hex = `AA ${hx(f.state)} ${hx(f.target)} ${hx(f.pos)} ${hx(f.chk)}`;
      return `<span class="fr">${hex}</span>  <span class="fb">${st(f.state)}</span> tgt=<b>${f.target}</b> pos=<b class="fpos">${f.pos}</b>`;
    });
    el.innerHTML = rows.length ? rows.join('\n') : '&mdash;';
  },

  /* ---------- main animation/rendering tick ---------- */
  _tick(now) {
    const dt = Math.min(50, now - this._lastFrameNow);   // cap to avoid spiral after tab switch
    this._lastFrameNow = now;

    // self-heal: an open serial port must never be left driving the DEMO sim.
    // (guards against a partial connect where mode was left on DEMO)
    if (this.state.connected && this.state.mode === 'DEMO') {
      this.log('Serial open · entering LIVE', 'info');
      this.setLinkUI(true);
      this.setMode('LIVE');
    }

    if (this.state.mode === 'DEMO') {
      // run simulation at 1ms physics steps (matches RTL tick = 1 ms)
      this._acc += dt;
      let guard = 0;
      while (this._acc >= 1 && guard < 60) { this.demo.step(1); this._acc -= 1; guard++; }
      if (guard === 60) this._acc = 0;                   // dropped behind -> resync
      this.state.position = this.demo.pos;
      this.state.velocity = this.demo.vel;
      this.state.target = this.demo.target;
      this.state.stateIdx = this.demo.state;
      if (this.demo.fault) this.state.stateIdx = 4;
      // emit a ~10 Hz sample like the FPGA telemetry does
      const tNow = Date.now();
      if (tNow - this._lastSample >= 100) { this._lastSample = tNow; this.pushSample(); }
    } else {
      // LIVE: comm watchdog
      if (this.state.connected) {
        const silent = Date.now() - this.state.lastFrameMs;
        if (this.state.lastFrameMs === 0) {
          // serial open but the FPGA has sent nothing yet
          if (!this._firstWarn && Date.now() - (this._connectAt || Date.now()) > 2000) {
            this._firstWarn = true;
            this.log('LINKED · waiting for first telemetry frame from FPGA', 'warn');
          }
        } else if (silent > 2000 && !this.state.commTimeout) {
          this.state.commTimeout = true;
          this.log('TELEMETRY TIMEOUT · no frame for 2 s', 'warn');
        } else if (silent <= 2000 && this.state.commTimeout) {
          this.state.commTimeout = false;
          this.log('TELEMETRY RESUMED', 'ok');
        }
      }
    }

    this._render();
    requestAnimationFrame(this._tick.bind(this));
  },

  /* render pose + HUD + state machine (rAF loop *and* every telemetry frame) */
  _render() {
    let dispPos;
    if (this.state.mode === 'DEMO') dispPos = this.demo.pos;
    else if (this.livePts.length === 0) dispPos = this.state.position;
    else {
      const nowMs = Date.now();
      if (this.livePts.length === 1) dispPos = this.livePts[0].pos;
      else {
        const [a, b] = this.livePts.slice(-2);
        if (nowMs >= b.t) dispPos = b.pos;
        else { const k = (nowMs - a.t) / Math.max(1, b.t - a.t); dispPos = a.pos + (b.pos - a.pos) * clamp(k, 0, 1); }
      }
    }
    const faulted = this.state.stateIdx === 4;
    Twin.draw(dispPos, this.state.target, faulted);   // draw() is null-safe
    if (dispPos != null && (this._lastDisp === undefined || Math.abs(dispPos - this._lastDisp) >= 1)) {
      Twin.updateTail(dispPos);
      this._lastDisp = dispPos;
    }
    this.updateHud();
    this.updateLinkMetrics();
  },

  /* ---------- DOM readout update (diffed so we never write unless changed) ---------- */
  updateHud() {
    const s = this.state;
    const posDisp = Math.round(s.position);
    const err = (s.target === null || s.position === null) ? null : s.target - s.position;
    const vel = (s.velocity === null || s.velocity === undefined) ? null : Math.round(s.velocity * 10) / 10;
    // cheap snapshot guard: numeric telemetry changes are the common cause of redraw
    const snap = s.stateIdx + '|' + (s.target ?? -1) + '|' + posDisp + '|' + (vel ?? 'x') + '|' + s.velSrc;
    if (snap === this._hudSnap) return;
    this._hudSnap = snap;

    $('valTarget').textContent = (s.target === null || s.target === undefined) ? '—' : Math.round(s.target);
    $('valActual').textContent = (s.position === null) ? '—' : posDisp;
    $('valError').textContent = (err === null) ? '—' : (Math.round(err * 10) / 10).toFixed(1);
    $('valError').style.color = (err !== null && Math.abs(err) <= 2) ? '#43e28b' : '#ffc05c';
    $('kvFault').textContent = (s.stateIdx === 4) ? 'FAULT' : 'NORMAL';
    $('kvFault').style.color = (s.stateIdx === 4) ? '#ff5c63' : '#43e28b';
    $('kvMotion').textContent = PROTO.STATES[s.stateIdx];
    $('faultBanner').classList.toggle('hidden', s.stateIdx !== 4);
    $('velLegend').textContent = (s.velSrc === 'est') ? 'EST (Δpos)' : (s.velSrc === 'model' ? 'MODEL (sim)' : 'N/A');

    if (vel === null) { $('valVelocity').textContent = 'N/A'; $('velUnit').textContent = ''; }
    else {
      $('valVelocity').textContent = String(vel);
      $('velUnit').textContent = (s.velSrc === 'est') ? 'deg/s EST' : 'deg/s';
    }
    this.updateStateFlow();
  },

  /* metrics / link / comm state — refresh at most every 250 ms */
  updateLinkMetrics(force) {
    const now = performance.now();
    if (!force && now - (this._lastMetrics || 0) < 250) return;
    this._lastMetrics = now;
    const st = this.parserStats;
    const s = this.state;
    $('linkPkts').textContent = String(st.valid);
    $('linkValidErr').textContent = st.valid + ' / ' + (st.checksumErr + st.invalid);
    const rate = (s.connected && s.mode === 'LIVE' && st.valid) ? this.parser.rateHz() : null;
    $('linkRate').textContent = rate ? rate.toFixed(1) + ' Hz' : '—';
    $('linkHz').textContent = rate ? rate.toFixed(1) + ' Hz' : '—';
    $('linkLast').textContent = s.connected
      ? (s.lastFrameMs ? timeStr(s.lastFrameMs) : 'waiting…')
      : '—';
    $('commWarn').classList.toggle('hidden', !s.commTimeout);

    const dot = $('linkDot'), txt = $('linkText');
    if (!s.connected) { dot.className = 'dot off'; txt.textContent = 'DISCONNECTED'; }
    else if (s.commTimeout) { dot.className = 'dot warn'; txt.textContent = 'TIMEOUT'; }
    else if (s.lastFrameMs) { dot.className = 'dot on'; txt.textContent = 'CONNECTED'; }
    else if (this._firstWarn) { dot.className = 'dot warn'; txt.textContent = 'NO DATA'; }
    else { dot.className = 'dot warn'; txt.textContent = 'LINKING…'; }
  },

  /* ---------- UI binding ---------- */
  bindUI() {
    $('btnConnect').addEventListener('click', () => {
      if (this.state.connected) return;
      if (this.state.mode === 'LIVE') return;
      this.connectLive();
    });
    $('btnDisconnect').addEventListener('click', () => this.disconnectLive());
    $('btnSend').addEventListener('click', () => this.doSend());
    $('ctrlTarget').addEventListener('keydown', (e) => { if (e.key === 'Enter') this.doSend(); });
    $('btnStop').addEventListener('click', () => this.doStop());
    $('btnReset').addEventListener('click', () => this.doReset());
    $('btnClearLog').addEventListener('click', () => this.logClear());
    $('btnRunDemo').addEventListener('click', () => this.toggleRunLoop());
    document.querySelectorAll('[data-exp]').forEach((b) =>
      b.addEventListener('click', () => {
        if (this.state.mode !== 'DEMO') return;
        const n = Number(b.dataset.exp);
        this.demoAutoStop();
        this.startExperiment(n);
      }));
  },

  doSend() {
    if (this.state.mode !== 'DEMO') return;
    const v = clamp(parseInt($('ctrlTarget').value, 10) || 0, 0, 180);
    $('ctrlTarget').value = v;
    const ok = this.demo.start(v);
    if (ok) { this.log(`TARGET SET = ${v}° · GO`, 'ok'); this.state.target = v; }
    else this.log('IGNORED · clear FAULT first', 'warn');
    this.updateControlUI();
  },
  doStop() {
    if (this.state.mode !== 'DEMO') return;
    this.demo.stop();
    this.log('STOP (demo) · motion frozen', 'info');
  },
  doReset() {
    if (this.state.mode !== 'DEMO') return;
    if (this.demo.fault) {
      this.demo.clear();
      this.log('FAULT ACK · back to IDLE', 'ok');
    } else {
      this.demo.clear();
      this.log('RESET · back to IDLE', 'info');
    }
    // drop the outstanding commanded target so the display agrees
    this.demo.target = this.demo.pos;
    this.state.target = this.demo.pos;
    this.state.stateIdx = this.demo.state;
  },
  startExperiment(n) {
    if (this.state.mode !== 'DEMO') return;
    const seq = { 1: [0, 90], 2: [90, 150], 3: [150, 30], 4: [0, 180] }[n];
    if (!seq) return;
    if (this.demo.fault) this.demo.clear();
    this.demo.start(seq[1]);
    this.log('EXPERIMENT ' + n + ' · target ' + seq[0] + '° → ' + seq[1] + '°', 'ok');
  },

  /* auto demo loop */
  runLoopOn: false,
  _loopSeq: [1, 2, 3, 4],
  toggleRunLoop() {
    this.runLoopOn = !this.runLoopOn;
    $('btnRunDemo').textContent = this.runLoopOn ? '■ STOP LOOP' : '▶ RUN DEMO LOOP';
    if (this.runLoopOn) { this.log('DEMO LOOP STARTED', 'info'); this._runNext(); }
    else this.log('DEMO LOOP STOPPED', 'dim');
  },
  _runNext() {
    if (!this.runLoopOn || this.state.mode !== 'DEMO') { this.runLoopOn = false; $('btnRunDemo').textContent = '▶ RUN DEMO LOOP'; return; }
    const n = this._loopSeq.shift(); this._loopSeq.push(n);
    this.startExperiment(n);
    // poll every 300 ms; when the pose settles at its target, start the next one
    const tgt = this.demo.target;
    const poll = setInterval(() => {
      if (this.state.mode !== 'DEMO' || !this.runLoopOn) { clearInterval(poll); this.runLoopOn = false; return; }
      if (this.demo.state === 3 && Math.abs(this.demo.target - this.demo.pos) <= 0.5) {
        clearInterval(poll);
        setTimeout(() => this._runNext(), 700);
      }
    }, 300);
  },

  updateControlUI() {
    const live = this.state.mode === 'LIVE';
    ['btnSend', 'btnStop', 'btnReset', 'btnRunDemo'].forEach((id) => { $(id).disabled = live; });
    document.querySelectorAll('[data-exp]').forEach((b) => { b.disabled = live; });
    $('ctrlTarget').disabled = live;
    $('ctrlHint').textContent = live
      ? 'LIVE mode = read-only monitor.  Set the target on the FPGA keypad (KEY0-9 then KEY11). FPGA has no UART RX command yet.'
      : 'Demo / future: target entry feeds the on-board trajectory → PID → virtual motor.';
  },

  setLinkUI(open) {
    $('btnConnect').disabled = open;
    $('btnDisconnect').disabled = !open;
  },

  updateSourceUI() {
    $('footSrc').textContent = (this.state.mode === 'LIVE')
      ? 'data source: EG4S20 FPGA over Web Serial'
      : 'data source: on-page DEMO model (mirrors rtl/virtual_motor + pid + trajectory)';
  },

  /* ---------- state flow diagram ---------- */
  buildStateFlow() {
    const host = $('stateFlow');
    const mk = (label, cls) => `<span class="state-node ${cls || ''}" data-s="${label}">${label}</span>`;
    // main chain + FAULT branch shown below, with the ACK path back to IDLE
    host.innerHTML =
      `<div class="state-row">` +
      mk('IDLE') + `<span class="state-arrow">→</span>` +
      mk('READY') + `<span class="state-arrow">→</span>` +
      mk('MOVE') + `<span class="state-arrow">→</span>` +
      mk('HOLD') +
      `</div>` +
      `<div class="state-row fault-branch">` +
      `<span class="state-arrow dim">from any state</span>` +
      mk('FAULT', 'fault-node') +
      `<span class="state-arrow dim">ACK → IDLE</span>` +
      `</div>`;
    this._stateEls = {};
    host.querySelectorAll('.state-node').forEach((n) => { this._stateEls[n.dataset.s] = n; });
    this.updateStateFlow();
  },
  updateStateFlow() {
    if (!this._stateEls) return;
    const cur = PROTO.STATES[this.state.stateIdx];
    for (const el of Object.values(this._stateEls)) el.classList.remove('active', 'fault-now');
    const curEl = this._stateEls[cur];
    if (curEl) {
      curEl.classList.add('active');
      if (cur === 'FAULT') curEl.classList.add('fault-now');
    }
  },

  /* ---------- event log ---------- */
  log(msg, tag = 'dim') {
    const ol = $('eventLog');
    const li = document.createElement('li');
    li.className = 'tag-' + tag;
    li.innerHTML = `<span class="t">${timeStr()}</span><span>${msg}</span>`;
    ol.insertBefore(li, ol.firstChild);
    while (ol.children.length > 120) ol.removeChild(ol.lastChild);
  },
  logClear() { $('eventLog').innerHTML = ''; },

  showWsError(msg) { const e = $('wsError'); e.textContent = msg; e.classList.remove('hidden'); },
  hideWsError() { $('wsError').classList.add('hidden'); },
};

/* =====================================================================
   Console self-tests for the parser (run without any hardware).
   Feed synthetic byte streams: single / split / multiple / garbage /
   bad checksum / payload containing 0xAA.
   ===================================================================== */
function runSelfTests() {
  const results = [];
  const mk = (st, tg, po) => {
    const ck = 0xAA ^ st ^ tg ^ po;
    return [0xAA, st, tg, po, ck];
  };
  const collect = () => { const rows = []; const p = new TelemetryParser((f) => rows.push(f)); return { p, rows }; };

  // 1) single complete frame
  {
    const { p, rows } = collect();
    p.push(mk(2, 90, 15));
    results.push(['single frame', rows.length === 1 && rows[0].state === 2 && rows[0].target === 90 && rows[0].pos === 15]);
  }
  // 2) split across reads (half + rest)
  {
    const { p, rows } = collect();
    const f = mk(3, 120, 118);
    p.push(f.slice(0, 2)); p.push(f.slice(2));
    results.push(['split frame', rows.length === 1 && rows[0].state === 3 && rows[0].target === 120 && rows[0].pos === 118]);
  }
  // 3) byte-by-byte (worst case fragmentation)
  {
    const { p, rows } = collect();
    const f = mk(1, 45, 12);
    for (const b of f) p.push(b);
    results.push(['byte-at-a-time', rows.length === 1 && rows[0].target === 45]);
  }
  // 4) multiple frames back to back
  {
    const { p, rows } = collect();
    p.push(mk(2, 30, 5).concat(mk(3, 60, 55)).concat(mk(3, 90, 90)));
    results.push(['3 glued frames', rows.length === 3 && rows[3 - 1] && rows[2].target === 90]);
  }
  // 5) garbage prefix then valid
  {
    const { p, rows } = collect();
    p.push([0x00, 0x55, 0xff, 0x01].concat(mk(0, 0, 0)));
    results.push(['garbage prefix', rows.length === 1 && rows[0].state === 0]);
  }
  // 6) corrupted checksum is rejected, next frame still parses
  {
    const { p, rows } = collect();
    const bad = mk(2, 90, 15); bad[4] ^= 0x55;
    p.push(bad.concat(mk(3, 150, 149)));
    results.push(['bad checksum skipped, resync', rows.length === 1 && rows[0].target === 150 && p._stats.checksumErr === 1]);
  }
  // 7) payload byte equal to 0xAA must not break framing
  {
    const { p, rows } = collect();
    p.push(mk(1, 170, 90));            // target=170 == 0xAA inside payload
    results.push(['0xAA inside payload', rows.length === 1 && rows[0].target === 170]);
  }
  // 8) random noise never crashes / reports
  {
    const { p, rows } = collect();
    const rnd = new Uint8Array(400); for (let i = 0; i < 400; i++) rnd[i] = Math.floor(Math.random() * 256);
    p.push(rnd);
    results.push(['random noise safe', Array.isArray(rows) && Number.isFinite(p._stats.invalid)]);
  }

  const failed = results.filter((r) => !r[1]);
  const out = { total: results.length, pass: results.length - failed.length, ok: failed.length === 0, failed };
  if (typeof console !== 'undefined') {
    console.log('%c TelemetryParser self-test ' + (out.ok ? 'PASS' : 'FAIL'), out.ok ? 'color:#43e28b' : 'color:#ff5c63', out);
    if (failed.length) failed.forEach((f) => console.warn('  FAILED:', f[0]));
  }
  return out;
}

/* ---------------- boot ---------------- */
window.addEventListener('DOMContentLoaded', () => Controller.init());
