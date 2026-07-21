const floatingRoot = document.querySelector<HTMLElement>(
  "[data-newsletter-signup]",
);

if (floatingRoot) {
  const submittedKey = "europa:newsletter:submitted:v1";
  const pendingKey = "europa:newsletter:pending:v1";
  const dismissedKey = "europa:newsletter:dismissed:v1";
  const shownKey = "europa:newsletter:shown:v1";
  const dismissalDuration = 7 * 24 * 60 * 60 * 1_000;
  const pendingDuration = 30 * 24 * 60 * 60 * 1_000;

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

  const readCurrentTimestamp = (
    storage: Storage,
    key: string,
    maximumAge: number,
  ) => {
    const stored = readStorage(storage, key);
    if (stored === null) return null;
    const timestamp = Number.parseInt(stored, 10);
    const age = Date.now() - timestamp;
    if (!Number.isFinite(timestamp) || age < 0 || age >= maximumAge) {
      removeStorage(storage, key);
      return null;
    }
    return timestamp;
  };

  const track = (eventName: string) => {
    window.europaAnalytics?.track(eventName);
  };

  let pageSubmitted = readFlag(window.localStorage, submittedKey);
  let pendingIsCurrent =
    readCurrentTimestamp(window.localStorage, pendingKey, pendingDuration) !==
    null;

  if (pageSubmitted || pendingIsCurrent) floatingRoot.hidden = true;

  const form = floatingRoot.querySelector<HTMLFormElement>(
    "[data-newsletter-form]",
  );
  const submit = floatingRoot.querySelector<HTMLButtonElement>(
    "[data-newsletter-submit]",
  );

  form?.addEventListener("submit", () => {
    if (submit) {
      submit.disabled = true;
      submit.setAttribute("aria-busy", "true");
    }
    track("signup-prompt-submitted");
  });

  window.addEventListener("pageshow", () => {
    pageSubmitted = readFlag(window.localStorage, submittedKey);
    pendingIsCurrent =
      readCurrentTimestamp(window.localStorage, pendingKey, pendingDuration) !==
      null;
    if (pageSubmitted || pendingIsCurrent) {
      floatingRoot.hidden = true;
      return;
    }
    if (submit) {
      submit.disabled = false;
      submit.removeAttribute("aria-busy");
    }
  });

  if (!pageSubmitted && !pendingIsCurrent) {
    const dismissalIsCurrent =
      readCurrentTimestamp(
        window.localStorage,
        dismissedKey,
        dismissalDuration,
      ) !== null;
    const shownThisSession = readFlag(window.sessionStorage, shownKey);
    const announcement = document.querySelector<HTMLElement>(
      "[data-newsletter-announcement]",
    );
    let activeSeconds = 0;
    let lastTick = performance.now();
    let lastScrollAt = performance.now();
    let lastBlockedAt = Number.NEGATIVE_INFINITY;
    let lastChapterInteractionAt = Number.NEGATIVE_INFINITY;
    let depthQualified = false;
    let promptRevealed = false;
    let promptDismissed = false;
    let focusBeforeReveal: HTMLElement | null = null;

    const dismissPrompt = () => {
      if (promptDismissed || pageSubmitted) return;
      const restoreFocus = floatingRoot.contains(document.activeElement);
      promptDismissed = true;
      floatingRoot.hidden = true;
      floatingRoot.classList.remove("is-visible");
      if (announcement) announcement.textContent = "";
      writeStorage(window.localStorage, dismissedKey, String(Date.now()));
      track("signup-prompt-dismissed");
      if (restoreFocus) {
        window.requestAnimationFrame(() => {
          if (focusBeforeReveal?.isConnected) {
            focusBeforeReveal.focus({ preventScroll: true });
            return;
          }
          (document.activeElement as HTMLElement | null)?.blur();
        });
      }
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

    const chapterSections = Array.from(
      document.querySelectorAll<HTMLElement>("[data-chapter-movement]"),
    );
    const journeySections = Array.from(
      document.querySelectorAll<HTMLElement>("[data-story-scene]"),
    );
    const depthSections =
      chapterSections.length > 0 ? chapterSections : journeySections;
    const requiredSections =
      chapterSections.length > 0
        ? Math.max(1, Math.ceil(chapterSections.length * 0.25))
        : Math.min(2, journeySections.length);
    let furthestSection = -1;

    const depthObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const index = depthSections.indexOf(entry.target as HTMLElement);
          furthestSection = Math.max(furthestSection, index);
        }
        depthQualified =
          requiredSections > 0 && furthestSection + 1 >= requiredSections;
        if (depthQualified) depthObserver.disconnect();
      },
      { threshold: 0.15 },
    );
    for (const section of depthSections) depthObserver.observe(section);

    const markChapterInteraction = (event: Event) => {
      if (
        event.target instanceof HTMLElement &&
        event.target.closest(".chapter-interaction")
      ) {
        lastChapterInteractionAt = performance.now();
      }
    };
    document.addEventListener("pointerdown", markChapterInteraction, true);
    document.addEventListener("input", markChapterInteraction, true);
    document.addEventListener("keydown", markChapterInteraction, true);

    const blockingUiIsOpen = () => {
      const chapterRegion = document.body.dataset.chapterRegion;
      const activeElement = document.activeElement;
      const activeInsideChapterInteraction =
        activeElement instanceof HTMLElement &&
        Boolean(activeElement.closest(".chapter-interaction"));
      const anotherFieldHasFocus =
        activeElement instanceof HTMLElement &&
        !floatingRoot.contains(activeElement) &&
        !activeInsideChapterInteraction &&
        activeElement.matches(
          "input, textarea, select, [contenteditable='true']",
        );

      return (
        document.body.classList.contains("chapter-route-open") ||
        chapterRegion === "act" ||
        chapterRegion === "ending" ||
        Boolean(document.querySelector("dialog[open]")) ||
        Boolean(document.querySelector("[role='dialog']:not([hidden])")) ||
        Boolean(
          document.querySelector("[data-analytics-consent]:not([hidden])"),
        ) ||
        anotherFieldHasFocus
      );
    };

    const revealPrompt = () => {
      focusBeforeReveal =
        document.activeElement instanceof HTMLElement &&
        document.activeElement !== document.body
          ? document.activeElement
          : null;
      promptRevealed = true;
      floatingRoot.hidden = false;
      writeStorage(window.sessionStorage, shownKey, "1");
      track("signup-prompt-shown");
      if (announcement) {
        announcement.textContent = "EUROPA email signup is available.";
      }
      window.requestAnimationFrame(() =>
        floatingRoot.classList.add("is-visible"),
      );
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

      const now = performance.now();
      const blockingUiOpen = blockingUiIsOpen();
      if (blockingUiOpen) lastBlockedAt = now;
      const blocked =
        blockingUiOpen ||
        now - lastScrollAt < 900 ||
        now - lastChapterInteractionAt < 8_000 ||
        now - lastBlockedAt < 8_000;

      if (promptRevealed) {
        if (floatingRoot.contains(document.activeElement)) {
          floatingRoot.hidden = false;
          return;
        }
        floatingRoot.hidden = blocked;
        return;
      }

      if (activeSeconds >= 35 && depthQualified && !blocked) revealPrompt();
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
