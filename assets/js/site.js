(() => {
  const root = document.documentElement;
  root.classList.remove("no-js");

  const header = document.querySelector(".site-header");
  const menuBtn = document.querySelector(".menu-btn");
  const pad = n => String(n).padStart(2, "0");

  if (header) {
    const onScroll = () => header.classList.toggle("scrolled", window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  if (header && menuBtn) {
    const setOpen = open => {
      header.classList.toggle("open", open);
      menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
    };
    menuBtn.addEventListener("click", () => setOpen(!header.classList.contains("open")));
    header.querySelectorAll(".navlinks a").forEach(a => a.addEventListener("click", () => setOpen(false)));
    document.addEventListener("keydown", e => { if (e.key === "Escape") setOpen(false); });
  }

  const clock = document.getElementById("clockChip");
  if (clock) {
    const tick = () => {
      const d = new Date();
      clock.textContent = pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()) + ":" + pad(d.getUTCSeconds()) + "Z";
    };
    tick();
    setInterval(tick, 1000);
  }

  const reveals = document.querySelectorAll(".reveal");
  if (reveals.length) {
    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver(entries => {
        entries.forEach(en => {
          if (!en.isIntersecting) return;
          en.target.classList.add("in");
          io.unobserve(en.target);
        });
      }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
      reveals.forEach(el => io.observe(el));
    } else {
      reveals.forEach(el => el.classList.add("in"));
    }
  }

  const links = [...document.querySelectorAll('.navlinks a[href^="#"]')];
  const targets = links.map(a => document.querySelector(a.getAttribute("href"))).filter(Boolean);
  if (targets.length && "IntersectionObserver" in window) {
    const spy = new IntersectionObserver(entries => {
      entries.forEach(en => {
        if (!en.isIntersecting) return;
        links.forEach(a => a.classList.toggle("active", a.getAttribute("href") === "#" + en.target.id));
      });
    }, { rootMargin: "-45% 0px -50% 0px" });
    targets.forEach(t => spy.observe(t));
  }

  document.querySelectorAll("[data-count]").forEach(el => {
    const target = Number(el.dataset.count);
    const suffix = el.dataset.suffix || "";
    if (!Number.isFinite(target)) return;
    const run = () => {
      const t0 = performance.now();
      const dur = 1200;
      const step = now => {
        const p = Math.min(1, (now - t0) / dur);
        el.textContent = Math.round(target * (1 - Math.pow(1 - p, 3))) + suffix;
        if (p < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    };
    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver(entries => {
        if (!entries[0].isIntersecting) return;
        io.disconnect();
        run();
      });
      io.observe(el);
    } else {
      el.textContent = target + suffix;
    }
  });
})();
