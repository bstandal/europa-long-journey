const movements = Array.from(
  document.querySelectorAll<HTMLElement>("[data-chapter-movement]"),
);
const stageImages = Array.from(
  document.querySelectorAll<HTMLImageElement>("[data-stage-image]"),
);
const stageStateImages = Array.from(
  document.querySelectorAll<HTMLImageElement>("[data-stage-state-owner]"),
);
const compareStages = Array.from(
  document.querySelectorAll<HTMLElement>("[data-compare-stage]"),
);
const inheritanceStages = Array.from(
  document.querySelectorAll<HTMLElement>("[data-inheritance-stage]"),
);
const routeMarkers = Array.from(
  document.querySelectorAll<HTMLElement>("[data-route-marker]"),
);
const routeLinks = Array.from(
  document.querySelectorAll<HTMLAnchorElement>("[data-route-link]"),
);
const routePeriod = document.querySelector<HTMLElement>("[data-route-period]");
const routePlace = document.querySelector<HTMLElement>("[data-route-place]");
const opening = document.querySelector<HTMLElement>(".chapter-opening");
const ending = document.querySelector<HTMLElement>(".chapter-ending");
const sources = document.querySelector<HTMLElement>(".chapter-sources");
const compact = window.matchMedia("(max-width: 720px)");

let activeIndex = 0;
let focusedMovementIndex: number | null = null;
let scrollFrame: number | undefined;

function setRoutePosition(movementId: string) {
  const activeLink = routeLinks.find((link) => link.dataset.routeLink === movementId);
  for (const marker of routeMarkers) {
    marker.classList.toggle("is-active", marker.dataset.routeMarker === movementId);
  }
  for (const link of routeLinks) {
    const active = link === activeLink;
    link.classList.toggle("is-active", active);
    if (active) link.setAttribute("aria-current", "location");
    else link.removeAttribute("aria-current");
  }
  if (!activeLink) return;
  if (routePeriod) routePeriod.textContent = activeLink.dataset.routePeriodValue ?? "";
  if (routePlace) routePlace.textContent = activeLink.dataset.routePlaceValue ?? "";
}

function setStageState(movementId: string, stateId: string) {
  const movementIsActive = movements.some(
    (movement) =>
      movement.dataset.movementId === movementId &&
      movement.classList.contains("is-active"),
  );
  for (const image of stageStateImages) {
    const ownsMovement = image.dataset.stageStateOwner === movementId;
    image.classList.toggle("is-owner-active", ownsMovement && movementIsActive);
    image.classList.toggle(
      "is-state-active",
      ownsMovement && movementIsActive && image.dataset.stageStateId === stateId,
    );
  }
}

function setInteractionAvailability(index: number | null) {
  for (const [movementIndex, movement] of movements.entries()) {
    const interaction = movement.querySelector<HTMLElement>(
      "[data-chapter-interaction]",
    );
    if (!interaction) continue;

    const available = compact.matches || movementIndex === index;
    if (!available && interaction.contains(document.activeElement)) {
      (document.activeElement as HTMLElement | null)?.blur();
    }
    interaction.inert = !available;
    if (available) interaction.removeAttribute("aria-hidden");
    else interaction.setAttribute("aria-hidden", "true");
  }
}

function setActiveMovement(index: number, updateHash = true) {
  const next = movements[index];
  if (!next) return;
  activeIndex = index;
  focusedMovementIndex = index;

  for (const [movementIndex, movement] of movements.entries()) {
    const active = movementIndex === index;
    movement.classList.toggle("is-active", active);
    if (active) movement.setAttribute("aria-current", "step");
    else movement.removeAttribute("aria-current");
  }
  setInteractionAvailability(index);

  for (const image of stageImages) {
    image.classList.toggle("is-active", image.dataset.stageImage === next.dataset.movementId);
  }
  for (const compareStage of compareStages) {
    compareStage.classList.toggle(
      "is-active",
      compareStage.dataset.compareStage === next.dataset.movementId,
    );
  }
  for (const inheritanceStage of inheritanceStages) {
    inheritanceStage.classList.toggle(
      "is-active",
      inheritanceStage.dataset.inheritanceStage === next.dataset.movementId,
    );
  }

  const interaction = next.querySelector<HTMLElement>("[data-chapter-interaction]");
  const stateId = interaction?.dataset.stateId ?? "";
  setStageState(next.dataset.movementId ?? "", stateId);
  setRoutePosition(next.dataset.movementId ?? "");

  if (interaction?.dataset.interactionKind === "seasons") {
    document.body.dataset.seasonTone = interaction.dataset.seasonTone ?? "";
  } else {
    delete document.body.dataset.seasonTone;
  }

  document.body.dataset.chapterMovement = next.dataset.movementId ?? "";
  document.body.dataset.chapterInteraction = next.dataset.interactionKind ?? "";
  document.body.dataset.chapterState = stateId;

  if (updateHash && next.id && window.location.hash !== `#${next.id}`) {
    window.history.replaceState(window.history.state, "", `#${next.id}`);
  }

}

function clearActiveMovement() {
  focusedMovementIndex = null;
  for (const movement of movements) {
    movement.classList.remove("is-active");
    movement.removeAttribute("aria-current");
  }
  setInteractionAvailability(null);
  for (const image of stageStateImages) image.classList.remove("is-owner-active");
  for (const compareStage of compareStages) compareStage.classList.remove("is-active");
  for (const inheritanceStage of inheritanceStages) {
    inheritanceStage.classList.remove("is-active");
  }
  document.body.dataset.chapterMovement = "";
  document.body.dataset.chapterInteraction = "";
  document.body.dataset.chapterState = "";
  delete document.body.dataset.seasonTone;
}

function chooseButton(button: HTMLButtonElement) {
  const interaction = button.closest<HTMLElement>("[data-chapter-interaction]");
  if (!interaction) return;
  const buttons = Array.from(
    interaction.querySelectorAll<HTMLButtonElement>("[data-interaction-choice]"),
  );
  for (const choice of buttons) {
    const active = choice === button;
    choice.classList.toggle("is-active", active);
    choice.setAttribute("aria-pressed", active ? "true" : "false");
  }

  const detail = interaction.querySelector<HTMLElement>("[data-interaction-detail]");
  if (detail) detail.textContent = button.dataset.detail ?? "";

  const choiceIndex = Number.parseInt(button.dataset.choiceIndex ?? "0", 10);
  const kind = interaction.dataset.interactionKind;

  if (kind === "seasons") {
    const stateId = button.dataset.stateId ?? "";
    interaction.dataset.stateId = stateId;
    interaction.dataset.seasonTone = button.dataset.tone ?? "";
    for (const state of interaction.querySelectorAll<HTMLElement>("[data-season-state]")) {
      state.hidden = state.dataset.seasonState !== stateId;
    }
    if (document.body.dataset.chapterMovement === interaction.dataset.movementId) {
      document.body.dataset.chapterState = stateId;
      document.body.dataset.seasonTone = button.dataset.tone ?? "";
    }
  }

  if (kind === "route") {
    for (const segment of interaction.querySelectorAll<SVGLineElement>(
      "[data-route-segment]",
    )) {
      const segmentIndex = Number.parseInt(segment.dataset.routeSegment ?? "0", 10);
      segment.classList.toggle("is-reached", segmentIndex <= choiceIndex);
    }
  }

  if (interaction.dataset.interactionKind === "lineage") {
    for (const record of interaction.querySelectorAll<HTMLElement>("[data-lineage-record]")) {
      record.hidden = Number.parseInt(record.dataset.lineageRecord ?? "-1", 10) !== choiceIndex;
    }
  }

  if (kind === "mobility") {
    for (const record of interaction.querySelectorAll<HTMLElement>("[data-mobility-record]")) {
      record.hidden =
        Number.parseInt(record.dataset.mobilityRecord ?? "-1", 10) !== choiceIndex;
    }
  }

  if (kind === "turnover") {
    for (const record of interaction.querySelectorAll<HTMLElement>("[data-turnover-record]")) {
      record.hidden =
        Number.parseInt(record.dataset.turnoverRecord ?? "-1", 10) !== choiceIndex;
    }
  }

  if (kind === "inheritance") {
    const stateId = button.dataset.stateId ?? "";
    interaction.dataset.stateId = stateId;
    for (const record of interaction.querySelectorAll<HTMLElement>(
      "[data-inheritance-record]",
    )) {
      record.hidden =
        Number.parseInt(record.dataset.inheritanceRecord ?? "-1", 10) !== choiceIndex;
    }
    for (const layer of interaction.querySelectorAll<HTMLElement>(
      "[data-inheritance-inline-layer]",
    )) {
      layer.classList.toggle(
        "is-active",
        layer.dataset.inheritanceInlineLayer === stateId,
      );
    }
    const movementId = interaction.dataset.movementId;
    const stage = inheritanceStages.find(
      (candidate) => candidate.dataset.inheritanceStage === movementId,
    );
    for (const layer of stage?.querySelectorAll<HTMLElement>(
      "[data-inheritance-layer]",
    ) ?? []) {
      layer.classList.toggle("is-active", layer.dataset.inheritanceLayer === stateId);
    }
  }

  if (button.dataset.stateId) {
    interaction.dataset.stateId = button.dataset.stateId;
    if (document.body.dataset.chapterMovement === interaction.dataset.movementId) {
      document.body.dataset.chapterState = button.dataset.stateId;
    }
  }
}

function setupHarvestControls() {
  document.querySelectorAll<HTMLElement>("[data-harvest-control]").forEach((control) => {
    const total = Number.parseInt(control.dataset.harvestTotal ?? "0", 10);
    const ranges = Array.from(
      control.querySelectorAll<HTMLInputElement>("[data-harvest-range]"),
    );
    const values = new Map(
      ranges.map((range) => [range.dataset.bucket ?? "", Number.parseInt(range.value, 10)]),
    );

    const updateHarvest = () => {
      let grainIndex = 0;
      const measures = Array.from(
        control.querySelectorAll<HTMLElement>("[data-grain-measure]"),
      );
      const shortages: string[] = [];

      for (const range of ranges) {
        const bucket = range.dataset.bucket ?? "";
        const value = values.get(bucket) ?? 0;
        const minimum = Number.parseInt(range.dataset.minimum ?? "0", 10);
        range.value = String(value);
        range.setAttribute(
          "aria-valuetext",
          `${value} of ${total} shares held for ${range.getAttribute("aria-label")?.split(",")[0]?.toLocaleLowerCase("en")}.`,
        );

        const output = control.querySelector<HTMLOutputElement>(
          `[data-harvest-output="${bucket}"]`,
        );
        if (output) output.value = String(value);

        for (let index = 0; index < value; index += 1) {
          const measure = measures[grainIndex];
          if (measure) measure.dataset.allocation = bucket;
          grainIndex += 1;
        }

        if (value < minimum) {
          if (bucket === "food") shortages.push("Winter hunger reaches the household.");
          if (bucket === "reserve") shortages.push("Spoilage or a long winter has no buffer.");
          if (bucket === "seed") shortages.push("The spring field must shrink.");
        }
      }

      for (const measure of measures.slice(grainIndex)) delete measure.dataset.allocation;
      const outcome = control.querySelector<HTMLElement>("[data-harvest-outcome]");
      const message = shortages.length
        ? shortages.join(" ")
        : "Food, a buffer and spring seed are all protected.";
      if (outcome) outcome.textContent = message;
      const detail = control
        .closest<HTMLElement>("[data-chapter-interaction]")
        ?.querySelector<HTMLElement>("[data-interaction-detail]");
      if (detail) detail.textContent = message;
    };

    for (const [changedIndex, range] of ranges.entries()) {
      range.addEventListener("input", () => {
        const bucket = range.dataset.bucket ?? "";
        const previous = values.get(bucket) ?? 0;
        let requested = Number.parseInt(range.value, 10);
        let delta = requested - previous;
        values.set(bucket, requested);

        const others = ranges
          .filter((other) => other !== range)
          .sort(
            (a, b) =>
              (values.get(b.dataset.bucket ?? "") ?? 0) -
              (values.get(a.dataset.bucket ?? "") ?? 0),
          );

        if (delta > 0) {
          for (const other of others) {
            if (delta <= 0) break;
            const otherBucket = other.dataset.bucket ?? "";
            const otherValue = values.get(otherBucket) ?? 0;
            const transferred = Math.min(otherValue, delta);
            values.set(otherBucket, otherValue - transferred);
            delta -= transferred;
          }
          if (delta > 0) {
            requested -= delta;
            values.set(bucket, requested);
          }
        } else if (delta < 0) {
          let released = Math.abs(delta);
          const recipients = [
            ...ranges.slice(changedIndex + 1),
            ...ranges.slice(0, changedIndex),
          ];
          for (const recipient of recipients) {
            if (released <= 0) break;
            const recipientBucket = recipient.dataset.bucket ?? "";
            const recipientValue = values.get(recipientBucket) ?? 0;
            const room = total - recipientValue;
            const transferred = Math.min(room, released);
            values.set(recipientBucket, recipientValue + transferred);
            released -= transferred;
          }
        }

        updateHarvest();
      });
    }

    updateHarvest();
  });
}

function setupInteractions() {
  document
    .querySelectorAll<HTMLButtonElement>("[data-interaction-choice]")
    .forEach((button) => {
      button.addEventListener("click", () => chooseButton(button));
    });

  setupHarvestControls();

  document.querySelectorAll<HTMLInputElement>("[data-growth-range]").forEach((range) => {
    const updateGrowthState = () => {
      const interaction = range.closest<HTMLElement>("[data-chapter-interaction]");
      if (!interaction) return;
      const stages = Array.from(
        interaction.querySelectorAll<HTMLElement>("[data-growth-stage]"),
      );
      const stageIndex = Number.parseInt(range.value, 10);
      const stageState = stages[stageIndex];
      if (!stageState) return;

      const detail = interaction.querySelector<HTMLElement>("[data-interaction-detail]");
      const settlement = interaction.querySelector<HTMLElement>("[data-growth-settlement]");
      const landscape = interaction.querySelector<HTMLElement>("[data-growth-landscape]");
      const labels = Array.from(
        interaction.querySelectorAll<HTMLElement>(".growth-control__labels span"),
      );
      const label = labels[stageIndex]?.textContent?.trim();
      const valueText = [
        label,
        stageState.dataset.settlement,
        stageState.dataset.landscape,
        stageState.dataset.detail,
      ].filter(Boolean);
      const stateId = stageState.dataset.growthStage ?? "";

      if (detail) detail.textContent = stageState.dataset.detail ?? "";
      if (settlement) settlement.textContent = stageState.dataset.settlement ?? "";
      if (landscape) landscape.textContent = stageState.dataset.landscape ?? "";
      interaction.dataset.stateId = stateId;
      setStageState(interaction.dataset.movementId ?? "", stateId);
      for (const image of interaction.querySelectorAll<HTMLElement>(
        "[data-growth-inline-image]",
      )) {
        image.classList.toggle("is-active", image.dataset.growthInlineImage === stateId);
      }
      if (document.body.dataset.chapterMovement === interaction.dataset.movementId) {
        document.body.dataset.chapterState = stateId;
      }
      range.setAttribute("aria-valuetext", valueText.join(". "));
    };

    range.addEventListener("input", updateGrowthState);
    updateGrowthState();
  });

  document.querySelectorAll<HTMLInputElement>("[data-compare-range]").forEach((range) => {
    const updateCompare = () => {
      const interaction = range.closest<HTMLElement>("[data-chapter-interaction]");
      if (!interaction) return;
      const progress = `${range.value}%`;
      const movementId = interaction.dataset.movementId;
      const compareStage = compareStages.find(
        (candidate) => candidate.dataset.compareStage === movementId,
      );
      compareStage?.style.setProperty("--compare-progress", progress);
      interaction
        .querySelector<HTMLElement>("[data-compare-inline]")
        ?.style.setProperty("--compare-progress", progress);
      const labels = Array.from(
        interaction.querySelectorAll<HTMLElement>(".compare-control__reveal > span"),
      ).map((label) => label.textContent?.trim());
      range.setAttribute(
        "aria-valuetext",
        `${labels[0] ?? "Earlier landscape"} remains to the left; ${labels[1] ?? "later landscape"} is revealed to the right.`,
      );
    };

    range.addEventListener("input", updateCompare);
    updateCompare();
  });
}

function updateMovementFromViewport(updateHash = true) {
  const openingIsVisible =
    (opening?.getBoundingClientRect().bottom ?? 0) >
    Math.max(96, window.innerHeight * 0.12);
  const endingIsVisible = [ending, sources].some((region) => {
    if (!region) return false;
    const bounds = region.getBoundingClientRect();
    return bounds.top < window.innerHeight && bounds.bottom > 0;
  });
  const pageRegionIsVisible = openingIsVisible || endingIsVisible;

  document.body.dataset.chapterRegion = openingIsVisible
    ? "opening"
    : endingIsVisible
      ? "ending"
      : "movement";
  if (openingIsVisible) {
    const firstMovementId = movements[0]?.dataset.movementId;
    if (firstMovementId) setRoutePosition(firstMovementId);
  }

  if (!compact.matches && pageRegionIsVisible) {
    if (focusedMovementIndex !== null) clearActiveMovement();
    else setInteractionAvailability(null);
    return;
  }

  const focusLine = window.innerHeight * 0.42;
  const index = movements.findIndex((movement) => {
    const bounds = movement.getBoundingClientRect();
    return bounds.top <= focusLine && bounds.bottom >= focusLine;
  });

  if (index >= 0) {
    if (focusedMovementIndex !== index || activeIndex !== index) {
      setActiveMovement(index, updateHash);
    } else {
      setInteractionAvailability(index);
    }
    return;
  }

  if (focusedMovementIndex !== null) clearActiveMovement();
  else setInteractionAvailability(null);
}

function scheduleMovementUpdate() {
  if (scrollFrame !== undefined) return;
  scrollFrame = window.requestAnimationFrame(() => {
    scrollFrame = undefined;
    updateMovementFromViewport();
  });
}

function updateRenderingMode() {
  updateMovementFromViewport(false);
}

function restoreHash() {
  const id = window.location.hash.replace(/^#/, "");
  const index = movements.findIndex((movement) => movement.id === id);
  if (index < 0) return;
  setActiveMovement(index, false);
  window.requestAnimationFrame(() => {
    movements[index].scrollIntoView({ block: "start", behavior: "auto" });
    scheduleMovementUpdate();
  });
}

setupInteractions();
setInteractionAvailability(null);
restoreHash();
updateMovementFromViewport(false);
document.body.classList.add("chapter-runtime-ready");

window.addEventListener("hashchange", restoreHash);
window.addEventListener("scroll", scheduleMovementUpdate, { passive: true });
window.addEventListener(
  "resize",
  () => {
    scheduleMovementUpdate();
  },
  { passive: true },
);

compact.addEventListener("change", updateRenderingMode);
updateRenderingMode();
