window.__umamiEvents = [];
window.umami = {
  track(...args) {
    window.__umamiEvents.push(args);
  },
};
