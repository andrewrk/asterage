const canvas = document.getElementById("app");
const context = canvas.getContext("2d");
const text_decoder = new TextDecoder();
const text_encoder = new TextEncoder();

let images = [];
let sounds = [];
let buttons = [
  { A: false, B: false, UP: false, DOWN: false, LEFT: false, RIGHT: false, START: false },
  { A: false, B: false, UP: false, DOWN: false, LEFT: false, RIGHT: false, START: false },
];
let wasm_exports = null;

canvas.focus();
context.imageSmoothingEnabled = false;

WebAssembly.instantiateStreaming(fetch("main.wasm"), {
  js: {
    log: function(ptr, len) {
      const msg = decodeString(ptr, len);
      console.log(msg);
    },
    panic: function (ptr, len) {
      const msg = decodeString(ptr, len);
      throw new Error("panic: " + msg);
    },
    buttons: function (ptr, len) {
      const bytes = new Uint8Array(wasm_exports.memory.buffer, ptr, len);
      for (let i = 0; i < 2; i += 1) {
        bytes[8*i+0] = buttons[i].A;
        bytes[8*i+1] = buttons[i].B;
        bytes[8*i+2] = buttons[i].UP;
        bytes[8*i+3] = buttons[i].DOWN;
        bytes[8*i+4] = buttons[i].LEFT;
        bytes[8*i+5] = buttons[i].RIGHT;
        bytes[8*i+6] = buttons[i].START;
      }
    },
    fillText: function(ptr, len, size, x, y) {
      const msg = decodeString(ptr, len);
      context.font = size + "px serif";
      context.fillStyle = "white";
      context.fillText(msg, x, y);
    },
    fillRect: function(color, rect) {
      const r = unwrapRect(rect);
      context.fillStyle = unwrapColor(color);
      context.fillRect(r.x, r.y, r.w, r.h);
    },
    drawImage: function(img, x, y, w, h, radians, scale) {
      context.save();
      context.translate(x, y);
      context.scale(scale, scale);
      context.rotate(radians);
      context.translate(-w/2 - x, -h/2 - y);
      context.drawImage(images[img], x, y, w, h);
      context.restore();
    },
    loadImage: function(ptr, len) {
      const path = decodeString(ptr, len);
      const img = new Image();
      img.src = path;
      images.push(img);
    },
    loadSound: function(ptr, len) {
      const path = decodeString(ptr, len);
      const sound = new Audio(path);
      sounds.push(sound);
    },
    playSound: function(sound) {
      sounds[sound].play();
    },
    seed: function() {
      return Math.random();
    },
  },
}).then(function(obj) {
  wasm_exports = obj.instance.exports;
  window.wasm = obj; // for debugging

  // For testing in browser, hook up the keyboard. The listeners will never
  // fire on the real arcade cabinet.
  addBrowserListeners();
  addCabinetListeners();
  wasm_exports.setup();
  update();
});

function addBrowserListeners() {
  window.addEventListener('keydown', onKeyDown);
  window.addEventListener('keyup', onKeyUp);
}

function removeBrowserListeners() {
  window.removeEventListener('keydown', onKeyDown);
  window.removeEventListener('keyup', onKeyUp);
}

function onKeyDown(ev) {
  switch (ev.code) {
    case "KeyW": buttons[0].UP = true; return;
    case "KeyA": buttons[0].LEFT = true; return;
    case "KeyS": buttons[0].DOWN = true; return;
    case "KeyD": buttons[0].RIGHT = true; return;
    case "KeyZ": buttons[0].A = true; return;
    case "KeyX": buttons[0].B = true; return;
    case "KeyI": buttons[1].UP = true; return;
    case "KeyJ": buttons[1].LEFT = true; return;
    case "KeyK": buttons[1].DOWN = true; return;
    case "KeyL": buttons[1].RIGHT = true; return;
    case "KeyN": buttons[1].A = true; return;
    case "KeyM": buttons[1].B = true; return;
  }
}

function onKeyUp(ev) {
  switch (ev.code) {
    case "KeyW": buttons[0].UP = false; return;
    case "KeyA": buttons[0].LEFT = false; return;
    case "KeyS": buttons[0].DOWN = false; return;
    case "KeyD": buttons[0].RIGHT = false; return;
    case "KeyZ": buttons[0].A = false; return;
    case "KeyX": buttons[0].B = false; return;
    case "KeyI": buttons[1].UP = false; return;
    case "KeyJ": buttons[1].LEFT = false; return;
    case "KeyK": buttons[1].DOWN = false; return;
    case "KeyL": buttons[1].RIGHT = false; return;
    case "KeyN": buttons[1].A = false; return;
    case "KeyM": buttons[1].B = false; return;
  }
}

function addCabinetListeners() {
  const name = "@rcade/input-classic";
  const version = "^1.0.0";
  const nonce = Math.random().toString(36).substring(2, 15) +
                Math.random().toString(36).substring(2, 15);

  window.addEventListener('message', onMessage);
  window.parent.postMessage({
      type: "acquire_plugin_channel",
      nonce: nonce,
      channel: { name: name, version: version },
  }, "*");

  function onMessage(ev) {
    if (event.data.type !== 'plugin_channel' || event.data.nonce !== nonce) return;

    window.removeEventListener('message', onMessage);
    removeBrowserListeners(); // Arcade cabinet mode detected.

    if (event.data.error != null) throw new Error(event.data.error);

    event.ports[0].onmessage = onPortMsg;

    function onPortMsg(ev) {
      if (ev.data.type === "button") {
        buttons[ev.data.player - 1][ev.data.button] = ev.data.pressed;
      } else if (ev.data.type === "system") {
        if (ev.data.button === "ONE_PLAYER") {
          buttons[0].START = true;
        } else if (ev.data.button === "TWO_PLAYER") {
          buttons[1].START = true;
        }
      }
    };
  }
}

function update() {
  context.clearRect(0, 0, canvas.width, canvas.height);
  wasm_exports.update();
  requestAnimationFrame(update);
}

function decodeString(ptr, len) {
  if (len === 0) return "";
  return text_decoder.decode(new Uint8Array(wasm_exports.memory.buffer, ptr, len));
}

function unwrapString(bigint) {
  const ptr = Number(bigint & 0xffffffffn);
  const len = Number(bigint >> 32n);
  return decodeString(ptr, len);
}

function unwrapRect(bigint) {
  return {
    x: Number((bigint >>  0n) & 0xffffn),
    y: Number((bigint >> 16n) & 0xffffn),
    w: Number((bigint >> 32n) & 0xffffn),
    h: Number((bigint >> 48n) & 0xffffn),
  };
}

function unwrapColor(x) {
    return "#" +
      hex(((x >>  0) & 0xff)) +
      hex(((x >>  8) & 0xff)) +
      hex(((x >> 16) & 0xff)) +
      hex(((x >> 24) & 0xff));
}

function wrapSize(w, h) {
  return (BigInt(h) << 0xffffn) | BigInt(w);
}

function hex(x) {
  const result = x.toString(16);
  return result.length === 1 ? "0" + result : result;
}
