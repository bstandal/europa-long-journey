import {
  Application,
  Assets,
  Container,
  Graphics,
  Sprite,
  Texture,
} from "pixi.js";
import { scenes, storyEras } from "../data/scenes";
import type {
  InteractionFamily,
  InteractionStep,
  MapCoordinate,
  MapScope,
} from "../types/story";

type SceneNode = HTMLElement & {
  dataset: {
    sceneId: string;
    order: string;
    era: string;
    latitude: string;
    longitude: string;
    cameraX: string;
    cameraY: string;
    cameraScale: string;
    cameraRotation: string;
    palette: string;
    mapScope: MapScope;
    transitionEffect: string;
  };
};

type ScenePoint = {
  id: string;
  order: number;
  era: string;
  title: string;
  latitude: number;
  longitude: number;
  x: number;
  y: number;
  scale: number;
  rotation: number;
  side: "left" | "right";
  period: string;
  mapScope: MapScope;
  element: SceneNode;
};

const clamp = (value: number, min = 0, max = 1) => Math.min(max, Math.max(min, value));
const lerp = (a: number, b: number, amount: number) => a + (b - a) * amount;
const ease = (value: number) => value * value * (3 - 2 * value);
const progressStorageKey = "europa:journey:v2";

const sceneNodes = Array.from(document.querySelectorAll<SceneNode>("[data-story-scene]"));
const journey = document.querySelector<HTMLElement>("[data-journey]");
const worldStage = document.querySelector<HTMLElement>("[data-world-stage]");
const canvas = document.querySelector<HTMLCanvasElement>("[data-world-canvas]");
const railYear = document.querySelector<HTMLElement>("[data-rail-year]");
const railChapter = document.querySelector<HTMLElement>("[data-rail-chapter]");
const railEra = document.querySelector<HTMLElement>("[data-rail-era]");
const railFill = document.querySelector<HTMLElement>("[data-rail-fill]");
const coordinates = document.querySelector<HTMLElement>("[data-coordinates]");
const mapLegend = document.querySelector<HTMLElement>("[data-map-legend]");
const railLinks = Array.from(document.querySelectorAll<HTMLAnchorElement>("[data-rail-link]"));
const chapterDialog = document.querySelector<HTMLDialogElement>("[data-chapter-dialog]");
const hotspotButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>("[data-map-hotspot]"),
);
const placeControls = Array.from(
  document.querySelectorAll<HTMLButtonElement>("[data-place-control]"),
);
const mobilePlaceButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>("[data-mobile-place]"),
);
const interactionPanels = Array.from(
  document.querySelectorAll<HTMLElement>("[data-interaction-panel]"),
);
const mobileInteractionPanels = Array.from(
  document.querySelectorAll<HTMLElement>("[data-mobile-interaction-panel]"),
);
const interactionStepButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>("[data-interaction-step]"),
);
const mapInsight = document.querySelector<HTMLElement>("[data-map-insight]");
const insightTitle = document.querySelector<HTMLElement>("[data-insight-title]");
const insightDetail = document.querySelector<HTMLElement>("[data-insight-detail]");
const insightCoordinates = document.querySelector<HTMLElement>("[data-insight-coordinates]");
const closeInsightButton = document.querySelector<HTMLButtonElement>("[data-close-insight]");
const mobilePreviousButton =
  document.querySelector<HTMLButtonElement>("[data-mobile-previous]");
const mobileNextButton = document.querySelector<HTMLButtonElement>("[data-mobile-next]");
const mobileSceneCount = document.querySelector<HTMLElement>("[data-mobile-scene-count]");
const mobileSceneTitle = document.querySelector<HTMLElement>("[data-mobile-scene-title]");
const mobileExplorerToggle =
  document.querySelector<HTMLButtonElement>("[data-mobile-explorer-toggle]");
const mobileExplorer = document.querySelector<HTMLElement>("[data-mobile-map-explorer]");
const closeMobileExplorerButton =
  document.querySelector<HTMLButtonElement>("[data-close-mobile-explorer]");
const mobileExplorerCount =
  document.querySelector<HTMLElement>("[data-mobile-explorer-count]");
const mobileExplorerTitle =
  document.querySelector<HTMLElement>("[data-mobile-explorer-title]");
const mobileExplorerTabs = Array.from(
  document.querySelectorAll<HTMLButtonElement>("[data-mobile-explorer-tab]"),
);
const mobileExplorerContents = Array.from(
  document.querySelectorAll<HTMLElement>("[data-mobile-explorer-content]"),
);
const journeyCta = document.querySelector<HTMLAnchorElement>("[data-journey-cta]");
const journeyCtaLabel = document.querySelector<HTMLElement>("[data-journey-cta-label]");
const journeyRestart = document.querySelector<HTMLAnchorElement>("[data-journey-restart]");
const dialogResumeWrap = document.querySelector<HTMLElement>("[data-dialog-resume-wrap]");
const dialogResume = document.querySelector<HTMLAnchorElement>("[data-dialog-resume]");
const dialogResumeTitle = document.querySelector<HTMLElement>("[data-dialog-resume-title]");
const chapterListItems = Array.from(
  document.querySelectorAll<HTMLElement>("[data-chapter-list-item]"),
);
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const compactQuery = window.matchMedia("(max-width: 720px)");
let compact = compactQuery.matches;

const points: ScenePoint[] = sceneNodes.map((element) => ({
  id: element.dataset.sceneId,
  order: Number(element.dataset.order),
  era: element.dataset.era,
  title: element.querySelector<HTMLElement>("h2")?.textContent?.trim() ?? "",
  latitude: Number(element.dataset.latitude),
  longitude: Number(element.dataset.longitude),
  x: Number(element.dataset.cameraX),
  y: Number(element.dataset.cameraY),
  scale: Number(element.dataset.cameraScale),
  rotation: Number(element.dataset.cameraRotation),
  side: element.classList.contains("story-scene--right") ? "right" : "left",
  period: element.querySelector<HTMLElement>(".scene-period")?.textContent?.trim() ?? "",
  mapScope: element.dataset.mapScope,
  element,
}));

let activeIndex = -1;
let activeInteractionStep = 0;
let activeMapScope: MapScope = "europe";
let frameRequested = false;
let mobileScrollRestoreTimer: number | undefined;
let sceneCenters: number[] = [];
let app: Application | undefined;
let europeWorld: Container | undefined;
let globalWorld: Container | undefined;
let europeMap: Sprite | undefined;
let globalMap: Sprite | undefined;
let routeActive: Graphics | undefined;
let routeGlow: Graphics | undefined;
let routeFracture: Graphics | undefined;
let routeMarkers: Graphics[] = [];
let europeInteraction: Graphics | undefined;
let globalInteraction: Graphics | undefined;
let europeWidth = 2550;
let europeHeight = 1410;
let globalWidth = 2400;
let globalHeight = 1200;
let globalLoadPromise: Promise<void> | undefined;
let europeTargetAlpha = 1;
let globalTargetAlpha = 0;
let insightPinned = false;
let activePlaceKey: string | undefined;
let activePlaceControl: HTMLButtonElement | undefined;
let suppressNextFocusPreview = false;
let lastPersistedSceneId: string | undefined;
let chapterDialogTrigger: HTMLButtonElement | undefined;

function formatCoordinate(value: number, positive: string, negative: string) {
  return `${Math.abs(Math.round(value))}° ${value >= 0 ? positive : negative}`;
}

function formatRailYear(period: string) {
  const first = period.split("–")[0]?.trim() ?? period;
  if (/^\d+$/.test(first) && period.includes("BC")) return `${first} BC`;
  return first;
}

function eraLabel(eraId: string) {
  return storyEras.find((era) => era.id === eraId)?.label ?? "";
}

function updateCenters() {
  sceneCenters = sceneNodes.map((scene) => {
    const rect = scene.getBoundingClientRect();
    return window.scrollY + rect.top + rect.height / 2;
  });
}

function locateProgress() {
  if (!sceneCenters.length) updateCenters();
  const cursor = window.scrollY + window.innerHeight * (compact ? 0.65 : 0.5);
  if (cursor <= sceneCenters[0]) return 0;
  const last = sceneCenters.length - 1;
  if (cursor >= sceneCenters[last]) return last;

  for (let index = 0; index < last; index += 1) {
    if (cursor >= sceneCenters[index] && cursor <= sceneCenters[index + 1]) {
      const span = sceneCenters[index + 1] - sceneCenters[index];
      return index + clamp((cursor - sceneCenters[index]) / span);
    }
  }
  return 0;
}

function projectScenePoint(point: ScenePoint) {
  return { x: point.x * europeWidth, y: point.y * europeHeight };
}

function projectCoordinates(point: MapCoordinate, scope = activeMapScope) {
  if (scope === "world") {
    return {
      x: clamp((point.longitude + 180) / 360) * globalWidth,
      y: clamp((90 - point.latitude) / 180) * globalHeight,
    };
  }
  return {
    x: clamp((point.longitude + 20) / 85) * europeWidth,
    y: clamp((72 - point.latitude) / 47) * europeHeight,
  };
}

function getPlaceKey(button: HTMLButtonElement) {
  return `${button.dataset.sceneId}:${button.dataset.hotspotId}`;
}

function restoreScrollPosition(position: number) {
  const root = document.documentElement;
  const applyPosition = () => window.scrollTo({ top: position, behavior: "auto" });
  root.classList.add("is-restoring-mobile-scroll");
  applyPosition();
  requestAnimationFrame(applyPosition);
  if (mobileScrollRestoreTimer !== undefined) window.clearTimeout(mobileScrollRestoreTimer);
  mobileScrollRestoreTimer = window.setTimeout(() => {
    applyPosition();
    root.classList.remove("is-restoring-mobile-scroll");
    mobileScrollRestoreTimer = undefined;
  }, 180);
}

function hideInsight(restoreFocus = false) {
  const controlToRestore = activePlaceControl;
  insightPinned = false;
  activePlaceKey = undefined;
  activePlaceControl = undefined;
  for (const control of placeControls) {
    control.classList.remove("is-open");
    control.setAttribute("aria-expanded", "false");
  }
  if (mapInsight) mapInsight.hidden = true;
  document.body.classList.remove("has-place-insight");
  if (restoreFocus) {
    requestAnimationFrame(() => {
      const focusTarget =
        controlToRestore &&
        !controlToRestore.hidden &&
        controlToRestore.getClientRects().length > 0
          ? controlToRestore
          : compact
            ? mobileExplorerToggle
            : undefined;
      if (!focusTarget) return;
      suppressNextFocusPreview = true;
      focusTarget.focus({ preventScroll: true });
      requestAnimationFrame(() => {
        suppressNextFocusPreview = false;
      });
    });
  }
}

function showInsight(button: HTMLButtonElement, pinned: boolean) {
  const key = getPlaceKey(button);
  activePlaceKey = key;
  activePlaceControl = button;
  insightPinned = pinned;
  for (const control of placeControls) {
    const isCurrent = getPlaceKey(control) === key;
    control.classList.toggle("is-open", isCurrent);
    control.setAttribute("aria-expanded", String(isCurrent));
  }
  if (insightTitle) insightTitle.textContent = button.dataset.label ?? "";
  if (insightDetail) insightDetail.textContent = button.dataset.detail ?? "";
  if (insightCoordinates) {
    const latitude = Number(button.dataset.latitude);
    const longitude = Number(button.dataset.longitude);
    insightCoordinates.textContent = `${formatCoordinate(latitude, "N", "S")} · ${formatCoordinate(
      longitude,
      "E",
      "W",
    )}`;
  }
  if (mapInsight) mapInsight.hidden = false;
  document.body.classList.add("has-place-insight");
  if (compact) {
    closeMobileExplorer();
    if (pinned) {
      requestAnimationFrame(() => closeInsightButton?.focus({ preventScroll: true }));
    }
  }
}

function closeMobileExplorer(preserveScroll = true) {
  if (!mobileExplorer || !mobileExplorerToggle) return;
  const scrollPosition =
    compact && preserveScroll && !mobileExplorer.hidden ? window.scrollY : undefined;
  const explorerHeldFocus = mobileExplorer.contains(document.activeElement);
  if (explorerHeldFocus && document.activeElement instanceof HTMLElement) {
    document.activeElement.blur();
  }
  mobileExplorer.hidden = true;
  mobileExplorerToggle.setAttribute("aria-expanded", "false");
  document.body.classList.remove("has-mobile-explorer");
  if (explorerHeldFocus) mobileExplorerToggle.focus({ preventScroll: true });
  if (scrollPosition !== undefined) {
    requestAnimationFrame(() => restoreScrollPosition(scrollPosition));
  }
}

function openMobileExplorer() {
  if (!mobileExplorer || !mobileExplorerToggle) return;
  const scrollPosition = compact ? window.scrollY : undefined;
  hideInsight();
  mobileExplorer.hidden = false;
  mobileExplorerToggle.setAttribute("aria-expanded", "true");
  document.body.classList.add("has-mobile-explorer");
  requestAnimationFrame(() => {
    if (scrollPosition !== undefined) restoreScrollPosition(scrollPosition);
    const selectedTab =
      mobileExplorerTabs.find((tab) => tab.getAttribute("aria-selected") === "true") ??
      mobileExplorerTabs[0];
    selectedTab?.focus({ preventScroll: true });
  });
}

function selectMobileExplorerTab(tabName: string, moveFocus = false) {
  const scrollPosition =
    compact && mobileExplorer && !mobileExplorer.hidden ? window.scrollY : undefined;
  let selectedTab: HTMLButtonElement | undefined;
  for (const tab of mobileExplorerTabs) {
    const selected = tab.dataset.mobileExplorerTab === tabName;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
    tab.classList.toggle("is-active", selected);
    if (selected) selectedTab = tab;
  }
  for (const content of mobileExplorerContents) {
    content.hidden = content.dataset.mobileExplorerContent !== tabName;
  }
  if (scrollPosition !== undefined || moveFocus) {
    requestAnimationFrame(() => {
      if (scrollPosition !== undefined) restoreScrollPosition(scrollPosition);
      if (moveFocus) selectedTab?.focus({ preventScroll: true });
    });
  }
}

function closeChapterDialog(restoreFocus = true) {
  if (!chapterDialog?.open) return;
  chapterDialog.close();
  if (restoreFocus && chapterDialogTrigger) {
    requestAnimationFrame(() => chapterDialogTrigger?.focus({ preventScroll: true }));
  }
}

function handleMobileExplorerTabKeydown(event: KeyboardEvent) {
  if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
  const currentIndex = mobileExplorerTabs.indexOf(event.currentTarget as HTMLButtonElement);
  if (currentIndex < 0) return;
  event.preventDefault();
  const lastIndex = mobileExplorerTabs.length - 1;
  const nextIndex =
    event.key === "Home"
      ? 0
      : event.key === "End"
        ? lastIndex
        : event.key === "ArrowLeft"
          ? (currentIndex - 1 + mobileExplorerTabs.length) % mobileExplorerTabs.length
          : (currentIndex + 1) % mobileExplorerTabs.length;
  const nextTab = mobileExplorerTabs[nextIndex];
  if (nextTab) selectMobileExplorerTab(nextTab.dataset.mobileExplorerTab ?? "story", true);
}

function updateMobileControls(index: number) {
  const current = points[index];
  const scene = scenes[index];
  for (const button of mobilePlaceButtons) {
    button.hidden = button.dataset.sceneId !== current.id;
  }
  if (mobileSceneCount) {
    mobileSceneCount.textContent = `${String(current.order).padStart(2, "0")} / ${String(points.length).padStart(2, "0")}`;
  }
  if (mobileSceneTitle) mobileSceneTitle.textContent = current.title;
  if (mobileExplorerCount) {
    mobileExplorerCount.textContent = `${scene.interaction.steps.length} views · ${scene.hotspots.length} places`;
  }
  if (mobileExplorerTitle) mobileExplorerTitle.textContent = scene.interaction.prompt;
  if (mobilePreviousButton) {
    mobilePreviousButton.disabled = index === 0;
    const previous = points[index - 1];
    mobilePreviousButton.setAttribute(
      "aria-label",
      previous ? `Previous chapter: ${previous.title}` : "Previous chapter",
    );
  }
  if (mobileNextButton) {
    mobileNextButton.disabled = index === points.length - 1;
    const next = points[index + 1];
    mobileNextButton.setAttribute(
      "aria-label",
      next ? `Next chapter: ${next.title}` : "Next chapter",
    );
  }
}

function moveToScene(index: number) {
  const point = points[index];
  if (!point) return;
  hideInsight();
  closeMobileExplorer(false);
  point.element.scrollIntoView({
    behavior: reduceMotion ? "auto" : "smooth",
    block: "start",
  });
  window.history.replaceState(null, "", `#${point.id}`);
}

function moveToLinkedScene(link: HTMLAnchorElement, event?: Event) {
  const sceneId = link.hash.replace(/^#/, "");
  const index = points.findIndex((point) => point.id === sceneId);
  if (index < 0) return;
  event?.preventDefault();
  chapterDialog?.close();
  moveToScene(index);
}

function activeContainer() {
  if (activeMapScope === "world" && globalWorld) return globalWorld;
  return europeWorld;
}

function updateHotspotPositions() {
  if (!worldStage || activeIndex < 0) return;
  const activeSceneId = points[activeIndex]?.id;
  const container = activeContainer();
  const stageWidth = worldStage.clientWidth;
  const stageHeight = worldStage.clientHeight;
  const mapWidth = activeMapScope === "world" ? globalWidth : europeWidth;
  const mapHeight = activeMapScope === "world" ? globalHeight : europeHeight;
  const scale = container?.scale.x ?? Math.max(stageWidth / mapWidth, stageHeight / mapHeight);
  const rotation = container?.rotation ?? 0;
  const pivotX = container?.pivot.x ?? mapWidth / 2;
  const pivotY = container?.pivot.y ?? mapHeight / 2;
  const positionX = container?.position.x ?? stageWidth / 2;
  const positionY = container?.position.y ?? stageHeight / 2;
  const cosine = Math.cos(rotation);
  const sine = Math.sin(rotation);
  const safeTop = compact ? 126 : 74;
  const safeBottom = compact ? 72 : 54;
  const candidates: {
    button: HTMLButtonElement;
    screenX: number;
    screenY: number;
    inFrame: boolean;
  }[] = [];

  for (const button of hotspotButtons) {
    if (button.dataset.sceneId !== activeSceneId) {
      button.hidden = true;
      continue;
    }

    const local = projectCoordinates(
      {
        latitude: Number(button.dataset.latitude),
        longitude: Number(button.dataset.longitude),
      },
      activeMapScope,
    );
    const relativeX = (local.x - pivotX) * scale;
    const relativeY = (local.y - pivotY) * scale;
    const screenX = positionX + relativeX * cosine - relativeY * sine;
    const screenY = positionY + relativeX * sine + relativeY * cosine;
    const inFrame =
      screenX > 22 &&
      screenX < stageWidth - 22 &&
      screenY > safeTop &&
      screenY < stageHeight - safeBottom;

    candidates.push({ button, screenX, screenY, inFrame });
  }

  const visibleCandidates = candidates.filter((candidate) => candidate.inFrame);
  if (compact && visibleCandidates.length > 1) {
    for (let index = 1; index < visibleCandidates.length; index += 1) {
      const previous = visibleCandidates[index - 1];
      const current = visibleCandidates[index];
      if (Math.hypot(previous.screenX - current.screenX, previous.screenY - current.screenY) < 54) {
        current.screenX = clamp(current.screenX + 32, 24, stageWidth - 24);
        current.screenY = clamp(current.screenY + 8, safeTop, stageHeight - safeBottom);
      }
    }
  }

  for (const candidate of candidates) {
    candidate.button.hidden = !candidate.inFrame;
    candidate.button.style.left = `${candidate.screenX}px`;
    candidate.button.style.top = `${candidate.screenY}px`;
  }
}

function drawRoute(progress: number) {
  if (!routeActive || !routeGlow || points.length < 2) return;
  routeActive.clear();
  routeGlow.clear();
  routeFracture?.clear();
  if (activeMapScope === "world") return;

  const segment = Math.min(points.length - 2, Math.floor(progress));
  const within = clamp(progress - segment);
  const start = projectScenePoint(points[0]);
  routeActive.moveTo(start.x, start.y);
  routeGlow.moveTo(start.x, start.y);

  for (let index = 1; index <= segment + 1; index += 1) {
    const point = projectScenePoint(points[index]);
    routeActive.lineTo(point.x, point.y);
    routeGlow.lineTo(point.x, point.y);
  }

  if (progress < points.length - 1) {
    const from = projectScenePoint(points[segment]);
    const to = projectScenePoint(points[segment + 1]);
    const current = {
      x: lerp(from.x, to.x, within),
      y: lerp(from.y, to.y, within),
    };
    routeActive.lineTo(current.x, current.y);
    routeGlow.lineTo(current.x, current.y);
  }

  routeGlow.stroke({ color: 0xc9964b, width: 13, alpha: 0.16, cap: "round", join: "round" });
  routeActive.stroke({ color: 0xf0c975, width: 3.1, alpha: 0.94, cap: "round", join: "round" });

  const fractureIndex = scenes.findIndex((scene) => scene.transitionEffect === "fracture");
  if (routeFracture && fractureIndex >= 0 && progress >= fractureIndex - 0.35) {
    const fracture = projectScenePoint(points[fractureIndex]);
    routeFracture
      .moveTo(fracture.x - 14, fracture.y - 14)
      .lineTo(fracture.x + 14, fracture.y + 14)
      .moveTo(fracture.x + 14, fracture.y - 14)
      .lineTo(fracture.x - 14, fracture.y + 14)
      .stroke({ color: 0xb84d3d, width: 3.2, alpha: 0.95, cap: "round" });
  }
}

function familyColor(family: InteractionFamily) {
  if (family === "network") return 0x8fc9c6;
  if (family === "boundary") return 0xca6c50;
  if (family === "compare") return 0xe6d7b8;
  return 0xf0c975;
}

function drawInteractionMarker(
  graphics: Graphics,
  coordinate: { x: number; y: number },
  family: InteractionFamily,
  color: number,
) {
  if (family === "network") {
    graphics
      .rect(coordinate.x - 5, coordinate.y - 5, 10, 10)
      .fill({ color, alpha: 0.96 })
      .rect(coordinate.x - 11, coordinate.y - 11, 22, 22)
      .stroke({ color, width: 1.2, alpha: 0.42 });
    return;
  }
  if (family === "boundary") {
    graphics
      .moveTo(coordinate.x, coordinate.y - 7)
      .lineTo(coordinate.x + 7, coordinate.y)
      .lineTo(coordinate.x, coordinate.y + 7)
      .lineTo(coordinate.x - 7, coordinate.y)
      .closePath()
      .fill({ color, alpha: 0.92 });
    return;
  }
  graphics
    .circle(coordinate.x, coordinate.y, 5.5)
    .fill({ color, alpha: 0.96 })
    .circle(coordinate.x, coordinate.y, 12)
    .stroke({ color, width: 1.2, alpha: 0.38 });
}

function drawInteractionStep(
  graphics: Graphics,
  step: InteractionStep,
  family: InteractionFamily,
  scope: MapScope,
) {
  graphics.clear();
  const projected = step.points.map((point) => projectCoordinates(point, scope));
  if (!projected.length) return;
  const color = familyColor(family);

  if (step.closed && projected.length > 2) {
    graphics.moveTo(projected[0].x, projected[0].y);
    for (const point of projected.slice(1)) graphics.lineTo(point.x, point.y);
    graphics.closePath();
    graphics.fill({ color, alpha: 0.12 });
    graphics.stroke({ color, width: 3, alpha: 0.82, join: "round" });
  } else {
    const links =
      step.links ??
      projected.slice(1).map((_, index) => [index, index + 1] as [number, number]);
    for (const [fromIndex, toIndex] of links) {
      const from = projected[fromIndex];
      const to = projected[toIndex];
      if (!from || !to) continue;
      graphics
        .moveTo(from.x, from.y)
        .lineTo(to.x, to.y)
        .stroke({
          color,
          width: family === "network" ? 2.2 : 3.2,
          alpha: family === "network" ? 0.72 : 0.9,
          cap: "round",
        });
    }
  }

  for (const point of projected) drawInteractionMarker(graphics, point, family, color);
}

function drawActiveInteraction() {
  const scene = scenes[activeIndex];
  if (!scene) return;
  const step = scene.interaction.steps[activeInteractionStep] ?? scene.interaction.steps[0];
  europeInteraction?.clear();
  globalInteraction?.clear();
  if (scene.interaction.mapScope === "world") {
    if (globalInteraction) drawInteractionStep(globalInteraction, step, scene.interaction.family, "world");
  } else if (europeInteraction) {
    drawInteractionStep(europeInteraction, step, scene.interaction.family, "europe");
  }
}

function updateInteractionControls() {
  const scene = scenes[activeIndex];
  if (!scene) return;
  for (const panel of interactionPanels) {
    panel.hidden = panel.dataset.sceneId !== scene.id;
  }
  for (const panel of mobileInteractionPanels) {
    panel.hidden = panel.dataset.sceneId !== scene.id;
  }
  for (const button of interactionStepButtons) {
    const isCurrentScene = button.dataset.sceneId === scene.id;
    const isActive =
      isCurrentScene && Number(button.dataset.stepIndex) === activeInteractionStep;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-pressed", String(isActive));
  }
  const summary = scene.interaction.steps[activeInteractionStep]?.summary ?? "";
  for (const panel of [...interactionPanels, ...mobileInteractionPanels]) {
    if (panel.dataset.sceneId !== scene.id) continue;
    const summaryNode = panel.querySelector<HTMLElement>("[data-interaction-summary]");
    if (summaryNode) summaryNode.textContent = summary;
  }
  if (mapLegend) mapLegend.textContent = scene.interaction.prompt.toUpperCase();
}

function setInteractionStep(stepIndex: number) {
  const scene = scenes[activeIndex];
  if (!scene) return;
  activeInteractionStep = clamp(stepIndex, 0, scene.interaction.steps.length - 1);
  updateInteractionControls();
  drawActiveInteraction();
}

async function ensureGlobalWorld() {
  if (globalWorld && globalMap) return;
  if (globalLoadPromise) return globalLoadPromise;
  globalLoadPromise = (async () => {
    if (!worldStage || !app) return;
    const worldMapUrl = worldStage.dataset.worldMap;
    if (!worldMapUrl) return;
    const texture = await Assets.load<Texture>(worldMapUrl);
    globalWidth = texture.width;
    globalHeight = texture.height;
    const container = new Container();
    container.alpha = 0;
    const map = new Sprite(texture);
    map.width = globalWidth;
    map.height = globalHeight;
    map.tint = 0xb6aa86;
    container.addChild(map);
    const shadow = new Graphics()
      .rect(0, 0, globalWidth, globalHeight)
      .fill({ color: 0x061118, alpha: 0.2 });
    container.addChild(shadow);
    globalInteraction = new Graphics();
    container.addChild(globalInteraction);
    globalWorld = container;
    globalMap = map;
    app.stage.addChildAt(container, 0);
    if (activeMapScope === "world") {
      europeTargetAlpha = 0;
      globalTargetAlpha = 1;
    }
    drawActiveInteraction();
    requestUpdate();
  })().catch(() => {
    globalLoadPromise = undefined;
  });
  return globalLoadPromise;
}

function setMapScope(scope: MapScope) {
  activeMapScope = scope;
  if (scope === "world") void ensureGlobalWorld();
  europeTargetAlpha = scope === "europe" ? 1 : 0;
  globalTargetAlpha = scope === "world" ? 1 : 0;
  document.body.dataset.mapScope = scope;
}

function updateResumeUi(sceneId: string) {
  const savedIndex = scenes.findIndex((scene) => scene.id === sceneId);
  if (savedIndex <= 0) return;
  const scene = scenes[savedIndex];
  if (journeyCta) journeyCta.href = `#${scene.id}`;
  if (journeyCtaLabel) journeyCtaLabel.textContent = `Continue at Chapter ${scene.order}`;
  if (journeyRestart) journeyRestart.hidden = false;
  if (dialogResumeWrap) dialogResumeWrap.hidden = false;
  if (dialogResume) dialogResume.href = `#${scene.id}`;
  if (dialogResumeTitle) dialogResumeTitle.textContent = scene.title;
  for (const item of chapterListItems) {
    const itemIndex = scenes.findIndex((candidate) => candidate.id === item.dataset.chapterListItem);
    item.classList.toggle("is-visited", itemIndex >= 0 && itemIndex <= savedIndex);
  }
}

function resetResumeUi() {
  const firstScene = scenes[0];
  lastPersistedSceneId = undefined;
  if (journeyCta) journeyCta.href = `#${firstScene.id}`;
  if (journeyCtaLabel) journeyCtaLabel.textContent = "Begin the journey";
  if (journeyRestart) journeyRestart.hidden = true;
  if (dialogResumeWrap) dialogResumeWrap.hidden = true;
  if (dialogResume) dialogResume.href = `#${firstScene.id}`;
  if (dialogResumeTitle) dialogResumeTitle.textContent = firstScene.title;
  for (const item of chapterListItems) item.classList.remove("is-visited");
}

function persistProgress(sceneId: string) {
  if (sceneId === lastPersistedSceneId) return;
  try {
    localStorage.setItem(progressStorageKey, sceneId);
    lastPersistedSceneId = sceneId;
    updateResumeUi(sceneId);
  } catch {
    // Progress persistence is an enhancement; the journey remains complete without it.
  }
}

function restoreProgress() {
  try {
    const sceneId = localStorage.getItem(progressStorageKey);
    if (sceneId && scenes.some((scene) => scene.id === sceneId)) {
      lastPersistedSceneId = sceneId;
      updateResumeUi(sceneId);
    }
  } catch {
    // Ignore storage restrictions.
  }
}

function setActive(index: number) {
  if (index === activeIndex) return;
  hideInsight();
  closeMobileExplorer(false);
  activeIndex = index;
  activeInteractionStep = 0;
  const current = points[index];
  const scene = scenes[index];

  for (const [sceneIndex, sceneNode] of sceneNodes.entries()) {
    const isActive = sceneIndex === index;
    sceneNode.classList.toggle("is-active", isActive);
    if (isActive) sceneNode.setAttribute("aria-current", "step");
    else sceneNode.removeAttribute("aria-current");
  }

  for (const link of railLinks) {
    if (link.dataset.railLink === current.id) link.setAttribute("aria-current", "step");
    else link.removeAttribute("aria-current");
  }

  if (railChapter) railChapter.textContent = String(current.order).padStart(2, "0");
  if (railYear) railYear.textContent = formatRailYear(current.period);
  if (railEra) railEra.textContent = eraLabel(current.era);
  if (coordinates) {
    coordinates.textContent = `${formatCoordinate(current.latitude, "N", "S")} · ${formatCoordinate(
      current.longitude,
      "E",
      "W",
    )}`;
  }
  document.body.dataset.era = current.element.dataset.palette;
  document.body.dataset.sceneSide = current.side;
  setMapScope(scene.interaction.mapScope);
  updateMobileControls(index);
  updateInteractionControls();
  drawActiveInteraction();
  updateHotspotPositions();
}

function updateWorld() {
  frameRequested = false;
  if (!points.length || !journey) return;

  const journeyRect = journey.getBoundingClientRect();
  const journeyActive =
    journeyRect.top < window.innerHeight * 0.55 &&
    journeyRect.bottom > window.innerHeight * 0.35;
  document.body.classList.toggle("journey-active", journeyActive);

  const rawProgress = locateProgress();
  const index = Math.min(points.length - 1, Math.max(0, Math.round(rawProgress)));
  setActive(index);
  if (journeyActive) persistProgress(points[index].id);
  if (index >= 12 && !globalWorld) void ensureGlobalWorld();

  const totalProgress = clamp(rawProgress / (points.length - 1));
  if (railFill) railFill.style.height = `${totalProgress * 100}%`;
  routeMarkers.forEach((marker, markerIndex) => {
    const distance = Math.abs(markerIndex - rawProgress);
    marker.alpha = markerIndex <= rawProgress + 0.35 ? 0.9 : Math.max(0.1, 0.3 - distance * 0.02);
  });

  if (!app || !europeWorld) {
    updateHotspotPositions();
    return;
  }

  if (activeMapScope === "world" && globalWorld) {
    const baseScale = Math.max(
      app.screen.width / globalWidth,
      app.screen.height / globalHeight,
    );
    globalWorld.pivot.set(globalWidth / 2, globalHeight / 2);
    globalWorld.position.set(app.screen.width / 2, app.screen.height / 2);
    globalWorld.scale.set(baseScale * (compact ? 1.02 : 1.04));
    globalWorld.rotation = 0;
    drawRoute(rawProgress);
    updateHotspotPositions();
    return;
  }

  if (compact || reduceMotion) {
    const current = points[index];
    const baseScale = Math.max(app.screen.width / europeWidth, app.screen.height / europeHeight);
    europeWorld.pivot.set(current.x * europeWidth, current.y * europeHeight);
    europeWorld.position.set(app.screen.width * 0.5, app.screen.height * 0.52);
    europeWorld.scale.set(baseScale * Math.max(1.05, current.scale * 0.82));
    europeWorld.rotation = 0;
    drawRoute(index);
    updateHotspotPositions();
    return;
  }

  const fromIndex = Math.min(points.length - 1, Math.floor(rawProgress));
  const toIndex = Math.min(points.length - 1, fromIndex + 1);
  const amount = ease(clamp(rawProgress - fromIndex));
  const from = points[fromIndex];
  const to = points[toIndex];
  const x = lerp(from.x, to.x, amount) * europeWidth;
  const y = lerp(from.y, to.y, amount) * europeHeight;
  const zoom = lerp(from.scale, to.scale, amount);
  const rotation = lerp(from.rotation, to.rotation, amount);
  const baseScale = Math.max(app.screen.width / europeWidth, app.screen.height / europeHeight);
  const focusX = lerp(from.side === "left" ? 0.69 : 0.31, to.side === "left" ? 0.69 : 0.31, amount);

  europeWorld.pivot.set(x, y);
  europeWorld.position.set(app.screen.width * focusX, app.screen.height * 0.5);
  europeWorld.scale.set(baseScale * zoom);
  europeWorld.rotation = rotation;
  drawRoute(rawProgress);
  updateHotspotPositions();
}

function requestUpdate() {
  if (frameRequested) return;
  frameRequested = true;
  requestAnimationFrame(updateWorld);
}

function setupControls() {
  const openButtons = document.querySelectorAll<HTMLButtonElement>("[data-open-index]");
  const closeButton = document.querySelector<HTMLButtonElement>("[data-close-index]");
  const jumpLinks = document.querySelectorAll<HTMLAnchorElement>("[data-dialog-jump]");

  openButtons.forEach((button) => {
    button.addEventListener("click", () => {
      chapterDialogTrigger = button;
      chapterDialog?.showModal();
    });
  });
  closeButton?.addEventListener("click", () => closeChapterDialog());
  jumpLinks.forEach((link) => {
    link.addEventListener("click", (event) => moveToLinkedScene(link, event));
  });
  railLinks.forEach((link) => {
    link.addEventListener("click", (event) => moveToLinkedScene(link, event));
  });
  journeyCta?.addEventListener("click", (event) => moveToLinkedScene(journeyCta, event));
  dialogResume?.addEventListener("click", (event) => moveToLinkedScene(dialogResume, event));
  chapterDialog?.addEventListener("click", (event) => {
    if (event.target === chapterDialog) closeChapterDialog();
  });
  chapterDialog?.addEventListener("cancel", (event) => {
    event.preventDefault();
    closeChapterDialog();
  });

  placeControls.forEach((button) => {
    button.addEventListener("mouseenter", () => {
      if (!compact && !insightPinned) showInsight(button, false);
    });
    button.addEventListener("mouseleave", () => {
      if (!compact && !insightPinned) hideInsight();
    });
    button.addEventListener("focus", () => {
      if (suppressNextFocusPreview) {
        suppressNextFocusPreview = false;
        return;
      }
      if (!compact && !insightPinned) showInsight(button, false);
    });
    button.addEventListener("blur", () => {
      if (!insightPinned) hideInsight();
    });
    button.addEventListener("click", () => {
      if (activePlaceKey === getPlaceKey(button) && insightPinned) hideInsight();
      else showInsight(button, true);
    });
  });

  interactionStepButtons.forEach((button) => {
    button.addEventListener("click", () => {
      if (button.dataset.sceneId !== scenes[activeIndex]?.id) return;
      setInteractionStep(Number(button.dataset.stepIndex));
    });
  });

  mobilePreviousButton?.addEventListener("click", () => moveToScene(activeIndex - 1));
  mobileNextButton?.addEventListener("click", () => moveToScene(activeIndex + 1));
  mobileExplorerToggle?.addEventListener("click", () => {
    if (mobileExplorer?.hidden) openMobileExplorer();
    else closeMobileExplorer();
  });
  closeMobileExplorerButton?.addEventListener("click", () => closeMobileExplorer());
  mobileExplorerTabs.forEach((tab) => {
    tab.addEventListener("click", () => selectMobileExplorerTab(tab.dataset.mobileExplorerTab ?? "story"));
    tab.addEventListener("keydown", handleMobileExplorerTabKeydown);
  });

  closeInsightButton?.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    window.setTimeout(() => hideInsight(true), 0);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    if (chapterDialog?.open) closeChapterDialog();
    else if (!mapInsight?.hidden) hideInsight(true);
    else if (!mobileExplorer?.hidden) closeMobileExplorer();
  });
  journeyRestart?.addEventListener("click", (event) => {
    try {
      localStorage.removeItem(progressStorageKey);
    } catch {
      // Ignore storage restrictions.
    }
    resetResumeUi();
    moveToLinkedScene(journeyRestart, event);
  });
}

async function setupWorld() {
  if (!worldStage || !canvas) return;
  const mapUrl = worldStage.dataset.map;
  const landmarkUrl = worldStage.dataset.landmarks;
  if (!mapUrl) return;

  app = new Application();
  await app.init({
    canvas,
    resizeTo: worldStage,
    antialias: true,
    autoDensity: true,
    backgroundAlpha: 0,
    resolution: Math.min(window.devicePixelRatio, compact ? 1.4 : 1.6),
    powerPreference: "high-performance",
  });

  const texture = await Assets.load<Texture>(mapUrl);
  europeWidth = texture.width;
  europeHeight = texture.height;
  europeWorld = new Container();
  app.stage.addChild(europeWorld);

  europeMap = new Sprite(texture);
  europeMap.width = europeWidth;
  europeMap.height = europeHeight;
  europeMap.tint = 0xc9b888;
  europeWorld.addChild(europeMap);

  const shadow = new Graphics()
    .rect(0, 0, europeWidth, europeHeight)
    .fill({ color: 0x071219, alpha: 0.08 });
  europeWorld.addChild(shadow);

  const routeBase = new Graphics();
  const first = projectScenePoint(points[0]);
  routeBase.moveTo(first.x, first.y);
  for (const point of points.slice(1)) {
    const projected = projectScenePoint(point);
    routeBase.lineTo(projected.x, projected.y);
  }
  routeBase.stroke({ color: 0xd7bd82, width: 2, alpha: 0.06, cap: "round", join: "round" });
  europeWorld.addChild(routeBase);

  routeGlow = new Graphics();
  europeWorld.addChild(routeGlow);
  routeActive = new Graphics();
  europeWorld.addChild(routeActive);
  routeFracture = new Graphics();
  europeWorld.addChild(routeFracture);

  routeMarkers = [];
  for (const [index, point] of points.entries()) {
    const projected = projectScenePoint(point);
    const marker = new Graphics()
      .circle(projected.x, projected.y, index === 0 ? 7 : 4.5)
      .fill({ color: 0xf1ca78, alpha: 0.9 })
      .circle(projected.x, projected.y, index === 0 ? 15 : 10)
      .stroke({ color: 0xe8bd68, width: 1.2, alpha: 0.4 });
    routeMarkers.push(marker);
    europeWorld.addChild(marker);
  }

  if (landmarkUrl) {
    try {
      const landmarkTexture = await Assets.load<Texture>(landmarkUrl);
      const panorama = new Sprite(landmarkTexture);
      panorama.anchor.set(0.5, 1);
      panorama.position.set(europeWidth * 0.52, europeHeight * 0.97);
      panorama.width = europeWidth * 0.98;
      panorama.height = Math.min(
        europeHeight * 0.31,
        panorama.height * (panorama.width / landmarkTexture.width),
      );
      panorama.alpha = 0.24;
      europeWorld.addChildAt(panorama, 2);
    } catch {
      // The optional atmospheric layer may fail without affecting the journey.
    }
  }

  europeInteraction = new Graphics();
  europeWorld.addChild(europeInteraction);
  app.ticker.add(() => {
    if (europeWorld) {
      europeWorld.alpha = reduceMotion
        ? europeTargetAlpha
        : lerp(europeWorld.alpha, europeTargetAlpha, 0.1);
    }
    if (globalWorld) {
      globalWorld.alpha = reduceMotion
        ? globalTargetAlpha
        : lerp(globalWorld.alpha, globalTargetAlpha, 0.1);
    }
  });

  document.body.classList.add("world-ready");
  updateCenters();
  drawActiveInteraction();
  requestUpdate();
}

setupControls();
restoreProgress();
updateCenters();
setActive(0);
selectMobileExplorerTab("story");
requestUpdate();

window.addEventListener("scroll", requestUpdate, { passive: true });
window.addEventListener("resize", () => {
  updateCenters();
  requestUpdate();
});
window.addEventListener("load", () => {
  updateCenters();
  const sceneId = window.location.hash.replace(/^#/, "");
  const index = points.findIndex((point) => point.id === sceneId);
  if (index >= 0) moveToScene(index);
  requestUpdate();
});
window.addEventListener("hashchange", () => {
  const sceneId = window.location.hash.replace(/^#/, "");
  const index = points.findIndex((point) => point.id === sceneId);
  if (index >= 0) moveToScene(index);
});
compactQuery.addEventListener("change", (event) => {
  compact = event.matches;
  closeMobileExplorer(false);
  updateCenters();
  requestUpdate();
});

void setupWorld().catch(() => {
  document.body.classList.remove("world-ready");
});
