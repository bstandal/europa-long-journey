const signupRoots = Array.from(
  document.querySelectorAll<HTMLElement>("[data-newsletter-signup]"),
);

if (signupRoots.length > 0) {
  const submittedKey = "europa:newsletter:submitted:v1";
  const pendingKey = "europa:newsletter:pending:v1";
  const dismissedKey = "europa:newsletter:dismissed:v1";
  const shownKey = "europa:newsletter:shown:v1";
  const dismissalDuration = 30 * 24 * 60 * 60 * 1_000;

  const readStorage = (storage: Storage, key: string) => {
    try {
      return storage.getItem(key);
    } catch {
      return null;
    }
  };

  const writeStorage = (storage: Storage, key: string, value: string) => {
    try {
      storage.setItem(key, value);
    } catch {
      // Storage may be unavailable in a hardened or private browser context.
    }
  };

  const removeStorage = (storage: Storage, key: string) => {
    try {
      storage.removeItem(key);
    } catch {
      // Storage may be unavailable in a hardened or private browser context.
    }
  };

  const readFlag = (storage: Storage, key: string) => {
    const value = readStorage(storage, key);
    if (value === "1") return true;
    if (value !== null) removeStorage(storage, key);
    return false;
  };

  const readCurrentTimestamp = (storage: Storage, key: string) => {
    const stored = readStorage(storage, key);
    if (stored === null) return null;
    const timestamp = Number.parseInt(stored, 10);
    const age = Date.now() - timestamp;
    if (!Number.isFinite(timestamp) || age < 0 || age >= dismissalDuration) {
      removeStorage(storage, key);
      return null;
    }
    return timestamp;
  };

  const track = (eventName: string) => {
    window.europaAnalytics?.track(eventName);
  };

  let pageSubmitted = readFlag(window.localStorage, submittedKey);
  let pendingAt = readCurrentTimestamp(window.localStorage, pendingKey);
  let pendingIsCurrent = pendingAt !== null;
  let promptDismissed = false;

  const inlineRoots = signupRoots.filter(
    (root) => root.dataset.newsletterVariant === "inline",
  );
  const floatingRoot = signupRoots.find(
    (root) => root.dataset.newsletterVariant === "floating",
  );

  if (pageSubmitted || pendingIsCurrent) {
    for (const root of signupRoots) root.hidden = true;
  } else {
    for (const root of inlineRoots) root.hidden = false;
  }

  for (const root of signupRoots) {
    const form = root.querySelector<HTMLFormElement>("[data-newsletter-form]");
    const submit = root.querySelector<HTMLButtonElement>("[data-newsletter-submit]");
    if (!form || !submit) continue;

    const expand = root.querySelector<HTMLButtonElement>("[data-newsletter-expand]");
    expand?.addEventListener("click", () => {
      expand.setAttribute("aria-expanded", "true");
      expand.hidden = true;
      form.hidden = false;
      root.classList.add("is-expanded");
      window.requestAnimationFrame(() => {
        form.querySelector<HTMLInputElement>("input[type='email']")?.focus();
      });
    });

    form.addEventListener("submit", () => {
      submit.disabled = true;
      submit.setAttribute("aria-busy", "true");
      track(
        root.dataset.newsletterVariant === "inline"
          ? "signup-inline-submitted"
          : "signup-prompt-submitted",
      );
    });
  }

  window.addEventListener("pageshow", () => {
    pageSubmitted = readFlag(window.localStorage, submittedKey);
    pendingAt = readCurrentTimestamp(window.localStorage, pendingKey);
    pendingIsCurrent = pendingAt !== null;
    if (pageSubmitted || pendingIsCurrent) {
      for (const root of signupRoots) root.hidden = true;
      return;
    }
    for (const root of inlineRoots) root.hidden = false;
    for (const submit of document.querySelectorAll<HTMLButtonElement>(
      "[data-newsletter-submit]",
    )) {
      submit.disabled = false;
      submit.removeAttribute("aria-busy");
    }
  });

  if (floatingRoot && !pageSubmitted && !pendingIsCurrent) {
    const dismissalIsCurrent =
      readCurrentTimestamp(window.localStorage, dismissedKey) !== null;
    const shownThisSession = readFlag(window.sessionStorage, shownKey);
    const announcement = document.querySelector<HTMLElement>(
      "[data-newsletter-announcement]",
    );
    let activeSeconds = 0;
    let lastTick = performance.now();
    let lastScrollAt = performance.now();
    let depthQualified = false;
    let promptRevealed = false;

    const dismissPrompt = () => {
      if (promptDismissed || pageSubmitted) return;
      promptDismissed = true;
      floatingRoot.hidden = true;
      floatingRoot.classList.remove("is-visible");
      if (announcement) announcement.textContent = "";
      writeStorage(window.localStorage, dismissedKey, String(Date.now()));
      track("signup-prompt-dismissed");
    };

    floatingRoot
      .querySelector<HTMLButtonElement>("[data-newsletter-dismiss]")
      ?.addEventListener("click", dismissPrompt);

    document.addEventListener("keydown", (event) => {
      if (
        event.key === "Escape" &&
        promptRevealed &&
        !floatingRoot.hidden &&
        !promptDismissed
      ) {
        dismissPrompt();
      }
    });

    const movements = Array.from(
      document.querySelectorAll<HTMLElement>("[data-chapter-movement]"),
    );
    let furthestMovement = -1;
    const depthObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const index = movements.indexOf(entry.target as HTMLElement);
          furthestMovement = Math.max(furthestMovement, index);
        }
        depthQualified =
          movements.length > 0 &&
          (furthestMovement + 1) / movements.length >= 0.5;
        if (depthQualified) depthObserver.disconnect();
      },
      { threshold: 0.15 },
    );
    for (const movement of movements) depthObserver.observe(movement);

    const blockingUiIsOpen = () => {
      const chapterRegion = document.body.dataset.chapterRegion;
      const activeElement = document.activeElement;
      const anotherFieldHasFocus =
        activeElement instanceof HTMLElement &&
        !floatingRoot.contains(activeElement) &&
        activeElement.matches("input, textarea, select, [contenteditable='true']");

      return (
        document.body.classList.contains("chapter-route-open") ||
        Boolean(document.body.dataset.chapterInteraction?.trim()) ||
        chapterRegion === "act" ||
        chapterRegion === "ending" ||
        Boolean(document.querySelector("dialog[open]")) ||
        Boolean(document.querySelector("[role='dialog']:not([hidden])")) ||
        Boolean(document.querySelector("[data-analytics-consent]:not([hidden])")) ||
        anotherFieldHasFocus
      );
    };

    const revealPrompt = () => {
      promptRevealed = true;
      floatingRoot.hidden = false;
      writeStorage(window.sessionStorage, shownKey, "1");
      track("signup-prompt-shown");
      if (announcement) {
        announcement.textContent =
          "A chapter update signup invitation is available.";
      }
      window.requestAnimationFrame(() => floatingRoot.classList.add("is-visible"));
    };

    const updatePrompt = () => {
      if (
        pageSubmitted ||
        pendingIsCurrent ||
        promptDismissed ||
        dismissalIsCurrent ||
        shownThisSession
      ) {
        floatingRoot.hidden = true;
        return;
      }

      const blocked =
        blockingUiIsOpen() || performance.now() - lastScrollAt < 900;

      if (promptRevealed) {
        if (
          floatingRoot.classList.contains("is-expanded") ||
          floatingRoot.contains(document.activeElement)
        ) {
          floatingRoot.hidden = false;
          return;
        }
        floatingRoot.hidden = blocked;
        return;
      }

      if (activeSeconds >= 60 && depthQualified && !blocked) revealPrompt();
    };

    window.addEventListener(
      "scroll",
      () => {
        lastScrollAt = performance.now();
      },
      { passive: true },
    );

    window.setInterval(() => {
      const now = performance.now();
      const elapsed = Math.min((now - lastTick) / 1_000, 2);
      lastTick = now;
      if (document.visibilityState === "visible") activeSeconds += elapsed;
      updatePrompt();
    }, 1_000);
  }
}

export {};
