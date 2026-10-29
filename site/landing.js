// Startseite: nur Darstellung und Bedienung, keine Daten, keine Anfragen nach außen.
(function () {
  const root = document.documentElement;
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  root.classList.add("js");

  // Einblenden beim Scrollen
  const reveal = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("visible");
      reveal.unobserve(entry.target);
    }
  }, { rootMargin: "0px 0px -8% 0px" });
  document.querySelectorAll(".reveal").forEach((element) => reveal.observe(element));

  // Aktiver Abschnitt in der Leiste
  const links = [...document.querySelectorAll(".nav-links a")];
  const spy = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      links.forEach((link) => link.classList.toggle("active", link.hash === "#" + entry.target.id));
    }
  }, { rootMargin: "-45% 0px -50% 0px" });
  links.forEach((link) => { const target = document.querySelector(link.hash); if (target) spy.observe(target); });

  // Kopf aus dem Bild: Buddy in der Leiste, Knopf „Nach oben“
  const hero = document.querySelector(".hero");
  new IntersectionObserver(([entry]) => {
    document.body.classList.toggle("past-hero", !entry.isIntersecting);
  }, { rootMargin: "-56px 0px 0px 0px" }).observe(hero);

  // Hell / dunkel: Wahl merken; ohne Wahl folgt die Seite dem System
  const themeColor = document.querySelector('meta[name="theme-color"]');
  const applyTheme = (theme) => {
    root.dataset.theme = theme;
    themeColor.content = theme === "dark" ? "#000000" : "#f2f2f7";
  };
  applyTheme(root.dataset.theme);
  document.querySelector("[data-theme-toggle]").addEventListener("click", () => {
    const theme = root.dataset.theme === "dark" ? "light" : "dark";
    applyTheme(theme);
    try { localStorage.setItem("theme", theme); } catch (error) {}
  });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (event) => {
    let stored = null;
    try { stored = localStorage.getItem("theme"); } catch (error) {}
    if (!stored) applyTheme(event.matches ? "dark" : "light");
  });

  // Sprachauswahl
  document.querySelectorAll("[data-menu]").forEach((menu) => {
    const button = menu.querySelector("button");
    const setOpen = (open) => { menu.classList.toggle("open", open); button.setAttribute("aria-expanded", open); };
    button.addEventListener("click", (event) => { event.stopPropagation(); setOpen(!menu.classList.contains("open")); });
    document.addEventListener("click", () => setOpen(false));
    document.addEventListener("keydown", (event) => { if (event.key === "Escape") setOpen(false); });
  });

  // Funktionskarten: Lichtschein folgt dem Zeiger
  document.querySelectorAll(".feature").forEach((card) => {
    card.addEventListener("pointermove", (event) => {
      const rect = card.getBoundingClientRect();
      card.style.setProperty("--mx", `${event.clientX - rect.left}px`);
      card.style.setProperty("--my", `${event.clientY - rect.top}px`);
    });
  });

  // Bilder: endlos (Kopien davor und dahinter), einrasten, Punkte, automatisch weiter, antippen = groß
  const lightbox = document.querySelector(".lightbox");
  const lightboxImage = lightbox.querySelector("img");
  let lightboxItems = [];
  let lightboxIndex = 0;
  const visibleImage = (figure) => [...figure.querySelectorAll("img")].find((image) => getComputedStyle(image).display !== "none");
  const showInLightbox = (index) => {
    lightboxIndex = (index + lightboxItems.length) % lightboxItems.length;
    const image = visibleImage(lightboxItems[lightboxIndex]);
    lightboxImage.src = image.currentSrc || image.src;
    lightboxImage.alt = image.alt;
    lightboxImage.classList.remove("swap");
    void lightboxImage.offsetWidth;
    lightboxImage.classList.add("swap");
  };
  lightbox.querySelector(".lb-close").addEventListener("click", () => lightbox.close());
  lightbox.querySelector(".lb-prev").addEventListener("click", () => showInLightbox(lightboxIndex - 1));
  lightbox.querySelector(".lb-next").addEventListener("click", () => showInLightbox(lightboxIndex + 1));
  lightbox.addEventListener("click", (event) => { if (event.target === lightbox) lightbox.close(); });
  lightbox.addEventListener("keydown", (event) => {
    if (event.key === "ArrowLeft") showInLightbox(lightboxIndex - 1);
    if (event.key === "ArrowRight") showInLightbox(lightboxIndex + 1);
  });

  const galleries = [...document.querySelectorAll(".gallery-wrap")].map((wrap) => {
    const gallery = wrap.querySelector(".gallery");
    const originals = [...gallery.querySelectorAll("figure")];
    const count = originals.length;
    const clone = (figure) => {
      const copy = figure.cloneNode(true);
      copy.setAttribute("aria-hidden", "true");
      copy.tabIndex = -1;
      return copy;
    };
    gallery.prepend(...originals.map(clone));
    gallery.append(...originals.map(clone));
    const figures = [...gallery.querySelectorAll("figure")];
    const dots = [...wrap.querySelectorAll(".dots button")];
    let current = count;
    let pausedUntil = 0;
    let settleTimer = 0;
    dots[0]?.classList.add("active");

    const centerOf = (figure) => figure.offsetLeft + figure.offsetWidth / 2 - gallery.clientWidth / 2;
    const jumpTo = (index) => {
      gallery.style.scrollSnapType = "none";
      gallery.scrollLeft = centerOf(figures[index]);
      gallery.style.scrollSnapType = "";
    };
    const nearest = () => {
      let best = 0;
      figures.forEach((figure, index) => {
        if (Math.abs(centerOf(figure) - gallery.scrollLeft) < Math.abs(centerOf(figures[best]) - gallery.scrollLeft)) best = index;
      });
      return best;
    };
    const markDot = () => dots.forEach((dot, index) => dot.classList.toggle("active", index === current % count));
    const go = (index) => {
      current = index;
      markDot();
      gallery.scrollTo({ left: centerOf(figures[index]), behavior: reduceMotion ? "auto" : "smooth" });
    };
    // Nach dem Scrollen: aus den Kopien unbemerkt in die Mitte zurückspringen
    gallery.addEventListener("scroll", () => {
      current = nearest();
      markDot();
      clearTimeout(settleTimer);
      settleTimer = setTimeout(() => {
        if (current < count || current >= 2 * count) {
          current = count + (current % count);
          jumpTo(current);
        }
      }, 140);
    }, { passive: true });

    const pause = () => { pausedUntil = Date.now() + 8000; };
    ["pointerdown", "wheel", "touchstart", "pointerenter", "focusin"].forEach((type) => gallery.addEventListener(type, pause, { passive: true }));
    dots.forEach((dot, index) => dot.addEventListener("click", () => { pause(); go(count + index); }));
    figures.forEach((figure, index) => {
      const open = () => {
        lightboxItems = originals;
        lightbox.showModal();
        showInLightbox(index % count);
      };
      figure.addEventListener("click", open);
      figure.addEventListener("keydown", (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); open(); } });
    });

    return {
      reset: () => { if (gallery.offsetParent !== null) { current = count; jumpTo(current); markDot(); } },
      tick: () => {
        if (Date.now() < pausedUntil || gallery.offsetParent === null || document.hidden || lightbox.open) return;
        go(current + 1);
      },
    };
  });
  // Erst nach dem Layout (Bilder haben feste Größen) und beim Wechsel iPad/iPhone mittig auf das erste Bild
  requestAnimationFrame(() => galleries.forEach((gallery) => gallery.reset()));
  window.addEventListener("load", () => galleries.forEach((gallery) => gallery.reset()));
  document.querySelectorAll(".gallery-input").forEach((input) => input.addEventListener("change", () => galleries.forEach((gallery) => gallery.reset())));
  if (!reduceMotion) setInterval(() => galleries.forEach((gallery) => gallery.tick()), 3500);

  // Stimmen: Laufband, das man auch selbst scrollen oder mit der Maus ziehen kann
  const reviews = document.querySelector(".reviews");
  const track = reviews?.querySelector(".reviews-track");
  if (track && !reduceMotion) {
    const originals = [...track.children];
    const copy = (card) => { const clone = card.cloneNode(true); clone.setAttribute("aria-hidden", "true"); return clone; };
    // Eine Hälfte muss breiter als das Fenster sein, sonst entsteht beim Übergang eine Lücke
    while (track.scrollWidth < window.innerWidth * 1.2) track.append(...originals.map(copy));
    track.append(...[...track.children].map(copy));
    const half = () => track.scrollWidth / 2;
    let pausedUntil = 0;
    let position = 0;
    let last = performance.now();
    const wrap = () => {
      if (reviews.scrollLeft >= half()) reviews.scrollLeft -= half();
      else if (reviews.scrollLeft <= 0) reviews.scrollLeft += half();
      position = reviews.scrollLeft;
    };
    const pause = (ms = 2500) => { pausedUntil = Math.max(pausedUntil, performance.now() + ms); };
    reviews.addEventListener("scroll", () => { if (Math.abs(reviews.scrollLeft - position) > 1) { pause(); wrap(); } }, { passive: true });
    reviews.addEventListener("pointerenter", () => pause(1e9));
    reviews.addEventListener("pointerleave", () => { pausedUntil = 0; pause(800); });
    // Ziehen mit der Maus (Touch und Trackpad scrollen von selbst)
    let drag = null;
    reviews.addEventListener("pointerdown", (event) => {
      if (event.pointerType !== "mouse") return;
      drag = { x: event.clientX, left: reviews.scrollLeft };
      reviews.classList.add("dragging");
      reviews.setPointerCapture(event.pointerId);
    });
    reviews.addEventListener("pointermove", (event) => { if (drag) reviews.scrollLeft = drag.left - (event.clientX - drag.x); });
    const endDrag = () => { drag = null; reviews.classList.remove("dragging"); };
    reviews.addEventListener("pointerup", endDrag);
    reviews.addEventListener("pointercancel", endDrag);
    const step = (now) => {
      const elapsed = now - last;
      last = now;
      if (now >= pausedUntil && !document.hidden) {
        position += elapsed * 0.03;
        reviews.scrollLeft = position;
        if (reviews.scrollLeft >= half()) { reviews.scrollLeft -= half(); position = reviews.scrollLeft; }
      }
      requestAnimationFrame(step);
    };
    requestAnimationFrame(() => { reviews.scrollLeft = position = half(); requestAnimationFrame(step); });
  }

  // Fragen: Suche über Frage und Antwort, Treffer markiert, Ergebnisse aufgeklappt
  const search = document.querySelector(".faq-search input");
  const empty = document.querySelector(".faq-empty");
  const entries = [...document.querySelectorAll(".faq details")].map((details) => {
    const summary = details.querySelector("summary");
    const answer = details.querySelector(".answer p");
    return { details, summary, answer, question: summary.innerHTML, text: answer.innerHTML };
  });
  const normalize = (text) => text.toLocaleLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  // Nur in Textknoten markieren, Links bleiben heil
  const mark = (html, words) => {
    if (!words.length) return html;
    const pattern = new RegExp(`(${words.map(escapeRegExp).join("|")})`, "gi");
    return html.split(/(<[^>]+>)/).map((part) => part.startsWith("<") ? part : part.replace(pattern, "<mark>$1</mark>")).join("");
  };
  search?.addEventListener("input", () => {
    const words = search.value.trim().split(/\s+/).filter(Boolean);
    const normalized = words.map(normalize);
    let shown = 0;
    for (const entry of entries) {
      const plain = normalize((entry.question + " " + entry.text).replace(/<[^>]+>/g, ""));
      const match = normalized.every((word) => plain.includes(word));
      entry.details.hidden = !match;
      entry.summary.innerHTML = mark(entry.question, words);
      entry.answer.innerHTML = mark(entry.text, words);
      if (match) shown += 1;
      const open = match && words.length > 0;
      entry.details.open = open;
      entry.details.classList.toggle("is-open", open);
      entry.details.classList.add("visible");
    }
    empty.hidden = shown > 0;
  });

  // Fragen: weich auf- und zuklappen
  document.querySelectorAll(".faq details").forEach((details) => {
    details.classList.toggle("is-open", details.open);
    details.addEventListener("toggle", () => { if (!details.dataset.animating) details.classList.toggle("is-open", details.open); });
    const summary = details.querySelector("summary");
    const answer = details.querySelector(".answer");
    summary.addEventListener("click", (event) => {
      if (reduceMotion) return;
      event.preventDefault();
      if (details.dataset.animating) return;
      details.dataset.animating = "1";
      const opening = !details.open;
      if (opening) details.open = true;
      const height = answer.scrollHeight;
      const frames = opening
        ? [{ height: "0px", opacity: 0, transform: "translateY(-6px)" }, { height: `${height}px`, opacity: 1, transform: "none" }]
        : [{ height: `${height}px`, opacity: 1, transform: "none" }, { height: "0px", opacity: 0, transform: "translateY(-6px)" }];
      details.classList.toggle("is-open", opening);
      answer.animate(frames, { duration: 320, easing: "cubic-bezier(0.2, 0.8, 0.2, 1)" }).finished.then(() => {
        if (!opening) details.open = false;
        delete details.dataset.animating;
      });
    });
  });
})();
