const floatingRoot = document.querySelector<HTMLElement>(
  "[data-newsletter-signup]",
);

if (floatingRoot) {
  const submittedKey = "europa:newsletter:submitted:v1";
  const dismissedKey = "europa:newsletter:dismissed:v1";
  const shownKey = "europa:newsletter:shown:v1";
  const dismissalDuration = 7 * 24 * 60 * 60 * 1_000;

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

  let pageSubmitted = readFlag(window.localStorage, submittedKey);

  if (pageSubmitted) floatingRoot.hidden = true;

  const form = floatingRoot.querySelector<HTMLFormElement>(
    "[data-newsletter-form]",
  );
  const submit = floatingRoot.querySelector<HTMLButtonElement>(
    "[data-newsletter-submit]",
  );
  const content = floatingRoot.querySelector<HTMLElement>(
    "[data-newsletter-content]",
  );
  const success = floatingRoot.querySelector<HTMLElement>(
    "[data-newsletter-success]",
  );
  const target = document.querySelector<HTMLIFrameElement>(
    "[data-newsletter-target]",
  );
  const dismiss = floatingRoot.querySelector<HTMLButtonElement>(
    "[data-newsletter-dismiss]",
  );
  const announcement = document.querySelector<HTMLElement>(
    "[data-newsletter-announcement]",
  );
  const error = floatingRoot.querySelector<HTMLElement>(
    "[data-newsletter-error]",
  );

  if (!pageSubmitted) {
    const dismissalIsCurrent =
      readCurrentTimestamp(
        window.localStorage,
        dismissedKey,
        dismissalDuration,
      ) !== null;
    const shownThisSession = readFlag(window.sessionStorage, shownKey);
    const chapterSections = Array.from(
      document.querySelectorAll<HTMLElement>("[data-chapter-movement]"),
    );
    const journeySections = Array.from(
      document.querySelectorAll<HTMLElement>("[data-story-scene]"),
    );
    const isChapterPage = chapterSections.length > 0;
    const requiredActiveSeconds = isChapterPage ? 10 : 35;
    let activeSeconds = 0;
    let lastTick = performance.now();
    let lastScrollAt = performance.now();
    let lastBlockedAt = Number.NEGATIVE_INFINITY;
    let lastChapterInteractionAt = Number.NEGATIVE_INFINITY;
    let depthQualified = isChapterPage;
    let promptRevealed = false;
    let promptDismissed = false;
    let focusBeforeReveal: HTMLElement | null = null;
    let submissionStarted = false;
    let submissionTimeout: number | undefined;
    let promptInterval: number | undefined;

    const restorePromptFocus = (restoreFocus: boolean) => {
      if (!restoreFocus) return;
      window.requestAnimationFrame(() => {
        if (focusBeforeReveal?.isConnected) {
          focusBeforeReveal.focus({ preventScroll: true });
          return;
        }
        (document.activeElement as HTMLElement | null)?.blur();
      });
    };

    const resetSubmit = () => {
      if (!submit) return;
      submit.disabled = false;
      submit.removeAttribute("aria-busy");
    };

    form?.addEventListener("submit", () => {
      submissionStarted = true;
      if (error) error.hidden = true;
      if (submit) {
        submit.disabled = true;
        submit.setAttribute("aria-busy", "true");
      }
      if (submissionTimeout !== undefined) {
        window.clearTimeout(submissionTimeout);
      }
      submissionTimeout = window.setTimeout(() => {
        if (!submissionStarted) return;
        submissionStarted = false;
        target?.setAttribute("src", "about:blank");
        resetSubmit();
        if (error) error.hidden = false;
        if (announcement) announcement.textContent = "Couldn’t send. Try again.";
      }, 15_000);
    });

    target?.addEventListener("load", () => {
      if (!submissionStarted || !target) return;
      let loadedPath: string;
      try {
        loadedPath = target.contentWindow?.location.pathname ?? "";
      } catch {
        return;
      }
      if (loadedPath !== target.dataset.newsletterReceiptPath) return;

      submissionStarted = false;
      if (submissionTimeout !== undefined) {
        window.clearTimeout(submissionTimeout);
      }
      if (promptInterval !== undefined) window.clearInterval(promptInterval);
      const restoreFocus = floatingRoot.contains(document.activeElement);
      pageSubmitted = true;
      writeStorage(window.localStorage, submittedKey, "1");
      removeStorage(window.localStorage, dismissedKey);
      if (content) content.hidden = true;
      if (dismiss) dismiss.hidden = true;
      if (success) success.hidden = false;
      floatingRoot.classList.add("is-sent");
      if (announcement) announcement.textContent = "You’re on the list.";
      restorePromptFocus(restoreFocus);
      window.setTimeout(() => {
        floatingRoot.classList.remove("is-visible");
        window.setTimeout(() => {
          floatingRoot.hidden = true;
        }, 240);
      }, 1_600);
    });

    window.addEventListener("pageshow", () => {
      pageSubmitted = readFlag(window.localStorage, submittedKey);
      if (pageSubmitted) {
        floatingRoot.hidden = true;
        return;
      }
      submissionStarted = false;
      if (submissionTimeout !== undefined) {
        window.clearTimeout(submissionTimeout);
      }
      resetSubmit();
    });

    const dismissPrompt = () => {
      if (promptDismissed || pageSubmitted) return;
      const restoreFocus = floatingRoot.contains(document.activeElement);
      promptDismissed = true;
      floatingRoot.hidden = true;
      floatingRoot.classList.remove("is-visible");
      if (announcement) announcement.textContent = "";
      writeStorage(window.localStorage, dismissedKey, String(Date.now()));
      restorePromptFocus(restoreFocus);
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

    if (!isChapterPage) {
      const requiredSections = Math.min(2, journeySections.length);
      let furthestSection = -1;
      const depthObserver = new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            if (!entry.isIntersecting) continue;
            const index = journeySections.indexOf(entry.target as HTMLElement);
            furthestSection = Math.max(furthestSection, index);
          }
          depthQualified =
            requiredSections > 0 && furthestSection + 1 >= requiredSections;
          if (depthQualified) depthObserver.disconnect();
        },
        { threshold: 0.15 },
      );
      for (const section of journeySections) depthObserver.observe(section);
    }

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
      if (announcement) {
        announcement.textContent = "EUROCENTRIC email signup is available.";
      }
      window.requestAnimationFrame(() =>
        floatingRoot.classList.add("is-visible"),
      );
    };

    const updatePrompt = () => {
      if (
        pageSubmitted ||
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

      if (
        activeSeconds >= requiredActiveSeconds &&
        depthQualified &&
        !blocked
      ) {
        revealPrompt();
      }
    };

    window.addEventListener(
      "scroll",
      () => {
        lastScrollAt = performance.now();
      },
      { passive: true },
    );

    promptInterval = window.setInterval(() => {
      const now = performance.now();
      const elapsed = Math.min((now - lastTick) / 1_000, 2);
      lastTick = now;
      if (document.visibilityState === "visible") activeSeconds += elapsed;
      updatePrompt();
    }, 1_000);
  }
}

export {};
