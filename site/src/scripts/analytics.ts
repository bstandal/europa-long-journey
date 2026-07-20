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
    };
  }
}

const trackerScript = document.querySelector<HTMLScriptElement>(
  "script[data-europa-analytics]",
);

if (trackerScript) {
  const queuedEvents: Array<[string, AnalyticsData | undefined]> = [];
  let trackerReady = false;
  let pageviewSent = false;

  const send = (eventName: string, data?: AnalyticsData) => {
    if (!trackerReady || !window.umami) {
      queuedEvents.push([eventName, data]);
      return;
    }
    window.umami.track(eventName, data);
  };

  window.europaAnalytics = { track: send };

  const startTracker = () => {
    if (trackerReady || !window.umami) return false;
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

  if (!startTracker()) {
    const startedAt = performance.now();
    const readyTimer = window.setInterval(() => {
      if (startTracker() || performance.now() - startedAt > 10_000) {
        window.clearInterval(readyTimer);
      }
    }, 100);
  }

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
    let nextHeartbeat = 30;
    let lastTick = performance.now();
    let engagedSent = false;

    window.setInterval(() => {
      const now = performance.now();
      const elapsed = Math.min((now - lastTick) / 1000, 2);
      lastTick = now;

      if (document.visibilityState !== "visible") return;
      activeSeconds += elapsed;

      if (!engagedSent && activeSeconds >= 15) {
        engagedSent = true;
        send("reader-engaged");
      }

      if (activeSeconds < nextHeartbeat) return;
      send("reader-active");
      nextHeartbeat = nextHeartbeat < 60 ? 60 : nextHeartbeat + 60;
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

  setupActiveReadingTime();
  setupChapterTracking();
  setupJourneyTracking();
}

export {};
