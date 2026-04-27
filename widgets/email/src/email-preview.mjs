export const EMAIL_PREVIEW_MESSAGES = [
  {
    id: "design-review-notes",
    sender: "Design",
    subject: "Review notes",
    avatar: "D",
    tint: "#FCAD59",
    unread: true,
  },
  {
    id: "linear-assigned-issues",
    sender: "Linear",
    subject: "3 issues assigned",
    avatar: "L",
    tint: "#B894FA",
    unread: true,
  },
  {
    id: "figma-prototype-ready",
    sender: "Figma",
    subject: "Updated prototype ready",
    avatar: "F",
    tint: "#63ADFA",
    unread: true,
  },
];

export const EMAIL_PREVIEW_UNREAD_COUNT = 5;

export function normalizePreviewMessages(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((message) => {
    if (!message || typeof message !== "object" || Array.isArray(message)) {
      return [];
    }

    const id = typeof message.id === "string" ? message.id.trim() : "";
    const sender = typeof message.sender === "string" ? message.sender.trim() : "";
    const subject = typeof message.subject === "string" ? message.subject.trim() : "";
    const fallbackAvatar = sender.slice(0, 1).toUpperCase();
    const avatar = typeof message.avatar === "string"
      ? message.avatar.trim().slice(0, 1).toUpperCase()
      : fallbackAvatar;
    const tint = typeof message.tint === "string" && message.tint.trim()
      ? message.tint.trim()
      : "#FA757A";

    if (!id || !sender || !subject) {
      return [];
    }

    const normalized = {
      id,
      sender,
      subject,
      avatar: avatar || fallbackAvatar || "?",
      tint,
      unread: message.unread !== false,
    };
    const uid = typeof message.uid === "string" ? message.uid.trim() : "";
    if (uid) {
      normalized.uid = uid;
    }

    return [normalized];
  });
}

export function unreadCount(messages) {
  return normalizePreviewMessages(messages).filter((message) => message.unread).length;
}
