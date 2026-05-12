const canvas = document.getElementById("app");
const ctx = canvas.getContext("2d");

let SYSTEM = {
  ONE_PLAYER: true,
};
let PLAYER_1 = {
  DPAD: { up: false, down: false, left: false, right: false },
  A: false,
  B: true,
};
let frameIndex = 0;

function update() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.font = "48px serif";
  ctx.fillStyle = "white";
  ctx.fillText("frame " + frameIndex, 1, 100);

  frameIndex += 1;
  requestAnimationFrame(update);
}

function disableImageSmoothing(context) {
  context.imageSmoothingEnabled = false;
  context.webkitImageSmoothingEnabled = false;
  context.mozImageSmoothingEnabled = false;
}

canvas.focus();
disableImageSmoothing(ctx);
update();
