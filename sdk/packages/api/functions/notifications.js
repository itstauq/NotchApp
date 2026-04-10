const { callRpc } = require("../runtime");

function scheduleNotification(id, payload = {}) {
  return callRpc("notifications.schedule", {
    id,
    title: payload.title,
    body: payload.body,
    deliverAtMs: payload.deliverAtMs,
  });
}

function cancelNotification(id) {
  return callRpc("notifications.cancel", { id });
}

module.exports = {
  scheduleNotification,
  cancelNotification,
};
