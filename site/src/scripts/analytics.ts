type AnalyticsValue = string | number | boolean;
type AnalyticsData = Record<string, AnalyticsValue>;

type UmamiTracker = {
  track: {
    (): unknown;
    (eventName: string, data?: AnalyticsData): unknown;
  };
};

declare global {
  interface Window {
    umami?: UmamiTracker;
    europaAnalytics?: {
      track: (eventName: string, data?: AnalyticsData) => void;
      openPreferences: () => void;
    };
  }
}

type ConsentChoice = "granted" | "denied";

const consentKey = "europa:analytics-consent:v1";
const analyticsConfig = document.querySelector<HTMLElement>(
  "[data-europa-analytics-config]",
);

if (analyticsConfig) {
  const consentPanel = document.querySelector<HTMLElement>(
    "[data-analytics-consent]",
  );
  const queuedEvents: Array<[string, AnalyticsData | undefined]> = [];
  let consentChoice: ConsentChoice | null = null;
  let measurementStarted = false;
  let trackerReady = false;
  let trackerUnavailable = false;
  let pageviewSent = false;
  let trackerScript: HTMLScriptElement | null = null;
  let readyTimer: number | null = null;
  let trackerGeneration = 0;

  const readConsent = (): ConsentChoice | null => {
    try {
      const stored = window.localStorage.getItem(consentKey);
      if (stored === "granted" || stored === "denied") return stored;
      if (stored !== null) window.localStorage.removeItem(consentKey);
    } catch {
      // A choice can still be used for this page when storage is unavailable.
    }
    return null;
  };

  const storeConsent = (choice: ConsentChoice) => {
    try {
      window.localStorage.setItem(consentKey, choice);
    } catch {
      // A hardened or private browser may not expose local storage.
    }
  };

  const send = (eventName: string, data?: AnalyticsData) => {
    if (consentChoice !== "granted" || trackerUnavailable) return;
    if (!trackerReady || !window.umami) {
      queuedEvents.push([eventName, data]);
      return;
    }
    window.umami.track(eventName, data);
  };

  const startTracker = () => {
    if (
      consentChoice !== "granted" ||
      trackerReady ||
      !window.umami
    ) {
      return false;
    }
    trackerReady = true;

    if (!pageviewSent) {
      pageviewSent = true;
      window.umami.track();
    }

    for (const [eventName, data] of queuedEvents.splice(0)) {
      window.umami.track(eventName, data);
    }
    return true;
  };

  const stopTracker = () => {
    trackerGeneration += 1;
    trackerReady = false;
    trackerUnavailable = false;
    queuedEvents.length = 0;
    if (readyTimer !== null) {
      window.clearInterval(readyTimer);
      readyTimer = null;
    }
    trackerScript?.remove();
    trackerScript = null;
    delete window.umami;
  };

  const waitForTracker = () => {
    const startedAt = performance.now();
    readyTimer = window.setInterval(() => {
      if (startTracker()) {
        if (readyTimer !== null) window.clearInterval(readyTimer);
        readyTimer = null;
        return;
      }
      if (performance.now() - startedAt > 10_000) {
        trackerUnavailable = true;
        queuedEvents.length = 0;
        if (readyTimer !== null) window.clearInterval(readyTimer);
        readyTimer = null;
      }
    }, 100);
  };

  const loadTracker = () => {
    if (
      consentChoice !== "granted" ||
      trackerScript ||
      trackerReady ||
      trackerUnavailable
    ) {
      return;
    }

    const scriptUrl = analyticsConfig.dataset.scriptUrl?.trim();
    const websiteId = analyticsConfig.dataset.websiteId?.trim();
    if (!scriptUrl || !websiteId) return;

    const generation = ++trackerGeneration;
    const script = document.createElement("script");
    trackerScript = script;
    script.defer = true;
    script.src = scriptUrl;
    script.dataset.europaAnalytics = "";
    script.dataset.websiteId = websiteId;
    script.dataset.domains = analyticsConfig.dataset.domains?.trim() ?? "";
    script.dataset.autoTrack = "false";
    script.dataset.excludeSearch = "true";
    script.dataset.excludeHash = "true";
    script.dataset.doNotTrack = "true";
    script.addEventListener("load", () => {
      if (
        generation !== trackerGeneration ||
        consentChoice !== "granted" ||
        trackerScript !== script
      ) {
        script.remove();
        if (consentChoice !== "granted") delete window.umami;
        return;
      }
      if (!startTracker() && readyTimer === null) waitForTracker();
    });
    script.addEventListener("error", () => {
      if (generation !== trackerGeneration || trackerScript !== script) return;
      trackerUnavailable = true;
      queuedEvents.length = 0;
    });
    document.head.append(script);
  };

  const trackOnce = (() => {
    const sent = new Set<string>();
    return (key: string, eventName = key) => {
      if (sent.has(key)) return;
      sent.add(key);
      send(eventName);
    };
  })();

  const setupActiveReadingTime = () => {
    let activeSeconds = 0;
    let lastTick = performance.now();
    const milestones = [
      { seconds: 15, event: "reader-engaged" },
      { seconds: 60, event: "reader-active-1m" },
      { seconds: 180, event: "reader-active-3m" },
      { seconds: 300, event: "reader-active-5m" },
      { seconds: 600, event: "reader-active-10m" },
      { seconds: 1_200, event: "reader-active-20m" },
    ];
    let nextMilestone = 0;

    window.setInterval(() => {
      const now = performance.now();
      const elapsed = Math.min((now - lastTick) / 1000, 2);
      lastTick = now;

      if (document.visibilityState !== "visible") return;
      activeSeconds += elapsed;

      while (
        nextMilestone < milestones.length &&
        activeSeconds >= milestones[nextMilestone].seconds
      ) {
        send(milestones[nextMilestone].event);
        nextMilestone += 1;
      }
    }, 1_000);
  };

  const setupDepthTracking = (
    elements: HTMLElement[],
    eventPrefix: "chapter" | "journey",
  ) => {
    if (elements.length === 0) return;
    let furthestIndex = -1;
    const milestones = [25, 50, 75];

    const record = (element: HTMLElement) => {
      const index = elements.indexOf(element);
      if (index <= furthestIndex) return;
      furthestIndex = index;
      const depth = ((furthestIndex + 1) / elements.length) * 100;
      for (const milestone of milestones) {
        if (depth >= milestone) {
          trackOnce(
            `${eventPrefix}-depth-${milestone}`,
            `${eventPrefix}-depth-${milestone}`,
          );
        }
      }
    };

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) record(entry.target as HTMLElement);
        }
      },
      { threshold: 0.15 },
    );

    for (const element of elements) observer.observe(element);
  };

  const setupChapterTracking = () => {
    const chapter = document.querySelector<HTMLElement>("[data-deep-chapter]");
    if (!chapter) return;

    const movements = Array.from(
      chapter.querySelectorAll<HTMLElement>("[data-chapter-movement]"),
    );
    setupDepthTracking(movements, "chapter");

    const ending = chapter.querySelector<HTMLElement>(".chapter-ending");
    if (ending) {
      const completionObserver = new IntersectionObserver(
        (entries) => {
          if (!entries.some((entry) => entry.isIntersecting)) return;
          trackOnce("chapter-complete");
          completionObserver.disconnect();
        },
        { threshold: 0.2 },
      );
      completionObserver.observe(ending);
    }

    const interactionKinds = new Set<string>();
    const recordInteraction = (target: EventTarget | null) => {
      if (!(target instanceof Element)) return;
      const interaction = target.closest<HTMLElement>("[data-chapter-interaction]");
      const kind = interaction?.dataset.interactionKind?.trim();
      if (!kind || interactionKinds.has(kind)) return;
      interactionKinds.add(kind);
      send(`interaction-${kind.replace(/[^a-z0-9-]+/gi, "-").toLowerCase()}`);
    };

    chapter.addEventListener("click", (event) => {
      if ((event.target as Element | null)?.closest("[data-interaction-choice]")) {
        recordInteraction(event.target);
      }
    });
    chapter.addEventListener("input", (event) => recordInteraction(event.target));
  };

  const setupJourneyTracking = () => {
    const scenes = Array.from(
      document.querySelectorAll<HTMLElement>("[data-story-scene]"),
    );
    if (scenes.length === 0) return;
    setupDepthTracking(scenes, "journey");

    document.querySelector("[data-journey-cta]")?.addEventListener("click", () => {
      trackOnce("journey-started");
    });

    const finalScene = scenes.at(-1);
    if (finalScene) {
      const completionObserver = new IntersectionObserver(
        (entries) => {
          if (!entries.some((entry) => entry.isIntersecting)) return;
          trackOnce("journey-complete");
          completionObserver.disconnect();
        },
        { threshold: 0.25 },
      );
      completionObserver.observe(finalScene);
    }
  };

  const startMeasurement = () => {
    if (measurementStarted) return;
    measurementStarted = true;
    setupActiveReadingTime();
    setupChapterTracking();
    setupJourneyTracking();
  };

  const showPreferences = () => {
    if (!consentPanel) return;
    for (const button of consentPanel.querySelectorAll<HTMLButtonElement>(
      "[data-analytics-choice]",
    )) {
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.analyticsChoice === consentChoice),
      );
    }
    consentPanel.hidden = false;
  };

  const applyConsent = (choice: ConsentChoice) => {
    consentChoice = choice;
    storeConsent(choice);
    if (consentPanel) {
      for (const button of consentPanel.querySelectorAll<HTMLButtonElement>(
        "[data-analytics-choice]",
      )) {
        button.setAttribute(
          "aria-pressed",
          String(button.dataset.analyticsChoice === choice),
        );
      }
      consentPanel.hidden = true;
    }

    if (choice === "granted") {
      trackerUnavailable = false;
      startMeasurement();
      loadTracker();
    } else {
      stopTracker();
    }
  };

  window.europaAnalytics = {
    track: send,
    openPreferences: showPreferences,
  };

  document.addEventListener("click", (event) => {
    if (!(event.target instanceof Element)) return;
    const choiceButton = event.target.closest<HTMLButtonElement>(
      "[data-analytics-choice]",
    );
    const choice = choiceButton?.dataset.analyticsChoice;
    if (choice === "granted" || choice === "denied") {
      applyConsent(choice);
      return;
    }
    if (event.target.closest("[data-analytics-preferences]")) showPreferences();
  });

  consentChoice = readConsent();
  if (consentChoice === "granted") {
    startMeasurement();
    loadTracker();
  } else if (consentChoice === null) {
    showPreferences();
  }
}

export {};
