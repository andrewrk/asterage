const canvas = document.getElementById("app");
const context = canvas.getContext("2d");

let buttons = [
  { A: false, B: false, UP: false, DOWN: false, LEFT: false, RIGHT: false, START: false },
  { A: false, B: false, UP: false, DOWN: false, LEFT: false, RIGHT: false, START: false },
];

let frameIndex = 0;

canvas.focus();
context.imageSmoothingEnabled = false;

listenInput();
update();

function listenInput() {
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

  context.font = "30px serif";
  context.fillStyle = "white";

  context.fillText("frame " + frameIndex, 1, 50);
  context.fillText("player 1: " + activeButtons(buttons[0]), 1, 100);
  context.fillText("player 2: " + activeButtons(buttons[1]), 1, 150);

  frameIndex += 1;
  requestAnimationFrame(update);
}

function activeButtons(o) {
  var s = "";
  for (key in o) {
    if (o[key]) s += key + ",";
  }
  return s;
}
