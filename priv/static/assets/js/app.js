// Phoenix HTML — form/button helpers
// Phoenix — channels
// Phoenix LiveView — real-time UI

// RangeDisplay hook — updates the sibling <span> as the slider moves.
// phx-change is not used here because it fires a server round-trip on every
// drag tick, causing latency and jank. A hook ties the listener lifecycle to
// the LiveView component so it is properly mounted/unmounted with the DOM.
const Hooks = {
  RangeDisplay: {
    mounted() {
      this.el.addEventListener("input", (e) => {
        const display = e.target.nextElementSibling;
        if (display) display.textContent = parseFloat(e.target.value).toFixed(2);
      });
    }
  }
};

// Initialise LiveSocket so phx-click, phx-submit, phx-change etc. work.
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks
});

liveSocket.connect();
window.liveSocket = liveSocket;

// Handle flash close
document.querySelectorAll("[role=alert][data-flash]").forEach((el) => {
  el.addEventListener("click", () => {
    el.setAttribute("hidden", "");
  });
});
