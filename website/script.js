/* Velo landing — interactions. Dependency-free; motion gated on reduced-motion. */
(function () {
  "use strict";
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var stage   = document.getElementById("hero-stage");
  var card    = document.getElementById("hero-card");
  var heroCopy= document.getElementById("hero-copy");
  var demoCopy= document.getElementById("demo-copy");
  var subject = document.querySelector(".hero-viz");
  var cue     = document.getElementById("scroll-cue");

  var clamp = function (v, a, b) { return Math.min(b, Math.max(a, v)); };
  var lerp  = function (a, b, t) { return a + (b - a) * t; };
  var smooth = function (t) { return t * t * (3 - 2 * t); };

  /* ---------- scroll-shrink hero ---------- */
  function dock() {
    var vw = window.innerWidth, vh = window.innerHeight;
    var dockW = Math.min(1180, vw * 0.92);
    // landscape card on desktop; give narrow screens a taller card so demo content fits
    var dockH = vw < 720 ? Math.min(vh * 0.72, 400) : Math.min(vh * 0.8, dockW * 0.6);
    return { vw: vw, vh: vh, dockW: dockW, dockH: dockH };
  }

  function updateHero() {
    if (reduce) return;
    var top = stage.offsetTop;
    var travel = stage.offsetHeight - window.innerHeight; // 100vh of scroll
    var p = clamp((window.scrollY - top) / (travel || 1), 0, 1);
    var e = smooth(p);
    var d = dock();

    card.style.width = lerp(d.vw, d.dockW, e) + "px";
    card.style.height = lerp(d.vh, d.dockH, e) + "px";
    card.style.borderRadius = lerp(0, 26, e) + "px";

    var heroOut = clamp(1 - p * 1.9, 0, 1);
    heroCopy.style.opacity = heroOut;
    heroCopy.style.transform = "scale(" + (1 - p * 0.08) + ")";
    subject.style.opacity = clamp(0.3 - p * 0.8, 0, 0.3);

    var demoIn = clamp((p - 0.55) / 0.33, 0, 1);
    demoCopy.style.opacity = demoIn;
    demoCopy.style.pointerEvents = demoIn > 0.6 ? "auto" : "none";
    cue.style.opacity = clamp(1 - p * 3, 0, 1);
  }

  if (reduce) {
    // collapse the scroll region; show a static full-bleed hero
    stage.style.height = "100vh";
    demoCopy.style.display = "none";
  } else {
    var ticking = false;
    var onScroll = function () {
      if (!ticking) { ticking = true; requestAnimationFrame(function () { updateHero(); ticking = false; }); }
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", updateHero);
    updateHero();
  }

  /* ---------- demo loop (types cleaned text into the docked field) ---------- */
  var demoText = document.getElementById("demo-text");
  var pillLabel = document.querySelector(".pill-label");
  var pillDot = document.querySelector(".demo-pill .pill-dot");
  if (demoText && !reduce) {
    var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
    var raw = "um so like i think we should ship friday";
    var clean = "I think we should ship Friday.";
    async function type(el, str, speed) {
      el.textContent = "";
      for (var i = 0; i < str.length; i++) { el.textContent += str[i]; await sleep(speed); }
    }
    async function runDemo() {
      while (true) {
        pillLabel.textContent = "Listening…"; pillDot.style.background = "";
        demoText.style.color = "rgba(255,255,255,.5)";
        await type(demoText, raw, 42);
        await sleep(500);
        pillLabel.textContent = "Cleaning up…";
        await sleep(650);
        demoText.style.color = "#fff";
        await type(demoText, clean, 34);
        pillLabel.textContent = "Inserted ✓";
        await sleep(1900);
        demoText.textContent = "";
        await sleep(500);
      }
    }
    runDemo();
  } else if (demoText) {
    demoText.textContent = "I think we should ship Friday.";
    if (pillLabel) pillLabel.textContent = "Inserted ✓";
  }

  /* ---------- per-app tone toggle ---------- */
  var bubble = document.getElementById("tone-bubble");
  var tones = {
    slack: "Sure — let's grab a call next week and I'll walk you through the details. Lmk what times work! 🙌",
    email: "Hi — I'd be happy to set up a call next week to walk through the details. Could you share a few times that work for you?",
    notes: "• Book a call next week\n• Walk through the details\n• Confirm their availability",
    code:  "// TODO: schedule call next week to review details with the client"
  };
  document.querySelectorAll(".seg-btn").forEach(function (btn) {
    btn.addEventListener("click", function () {
      document.querySelectorAll(".seg-btn").forEach(function (b) { b.classList.remove("is-active"); });
      btn.classList.add("is-active");
      var t = btn.getAttribute("data-tone");
      bubble.style.opacity = "0";
      setTimeout(function () {
        bubble.textContent = tones[t];
        bubble.style.whiteSpace = (t === "notes" || t === "code") ? "pre-line" : "normal";
        bubble.style.fontFamily = (t === "code") ? "var(--font-mono)" : "var(--font-body)";
        bubble.style.fontSize = (t === "code") ? "13.5px" : "16px";
        bubble.style.background = (t === "code")
          ? "linear-gradient(135deg,#3f3f46,#27272a)"
          : "linear-gradient(135deg,#2563eb,#3b82f6)";
        bubble.style.opacity = "1";
      }, reduce ? 0 : 180);
    });
  });

  /* ---------- scroll reveals ---------- */
  var reveals = document.querySelectorAll("[data-reveal]");
  if ("IntersectionObserver" in window && !reduce) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) { if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); } });
    }, { rootMargin: "0px 0px -10% 0px", threshold: 0.12 });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add("in"); });
  }

  if (reduce) return;

  /* ---------- cursor glow ---------- */
  var glow = document.querySelector(".cursor-glow");
  var tx = innerWidth / 2, ty = innerHeight * 0.4, cx = tx, cy = ty, pend = false;
  function paint() {
    pend = false;
    cx += (tx - cx) * 0.12; cy += (ty - cy) * 0.12;
    glow.style.setProperty("--mx", cx + "px");
    glow.style.setProperty("--my", cy + "px");
    if (Math.abs(tx - cx) > 0.5 || Math.abs(ty - cy) > 0.5) { pend = true; requestAnimationFrame(paint); }
  }
  addEventListener("pointermove", function (e) { tx = e.clientX; ty = e.clientY; if (!pend) { pend = true; requestAnimationFrame(paint); } }, { passive: true });

  /* ---------- footer wordmark equalizer ---------- */
  var fw = document.querySelector("[data-eq]");
  var fbars = fw ? fw.querySelectorAll(".fbar") : [];
  var wordText = document.querySelector(".footer-text");
  if (fw && fbars.length) {
    fw.addEventListener("pointermove", function (e) {
      var rect = fw.getBoundingClientRect();
      if (wordText) wordText.style.setProperty("--sweep", (((e.clientX - rect.left) / rect.width) * 100).toFixed(1) + "%");
      var sr = fw.querySelector(".footer-mark").getBoundingClientRect();
      fbars.forEach(function (bar) {
        var b = bar.getBoundingClientRect();
        var dist = Math.abs(e.clientX - (b.left + b.width / 2)) / sr.width;
        bar.style.transform = "scaleY(" + (1 + Math.max(0, 0.55 - dist) * 1.1).toFixed(3) + ")";
      });
    }, { passive: true });
    fw.addEventListener("pointerleave", function () { fbars.forEach(function (b) { b.style.transform = ""; }); });
  }
})();
