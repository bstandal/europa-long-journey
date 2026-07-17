import {
  Application,
  Assets,
  Container,
  Graphics,
  Sprite,
  Texture,
} from "pixi.js";

type SceneNode = HTMLElement & {
  dataset: {
    sceneId: string;
    order: string;
    latitude: string;
    longitude: string;
    cameraX: string;
    cameraY: string;
    cameraScale: string;
    cameraRotation: string;
    palette: string;
  };
};

type ScenePoint = {
  id: string;
  order: number;
  title: string;
  latitude: number;
  longitude: number;
  x: number;
  y: number;
  scale: number;
  rotation: number;
  side: "left" | "right";
  period: string;
  element: SceneNode;
};

const clamp = (value: number, min = 0, max = 1) => Math.min(max, Math.max(min, value));
const lerp = (a: number, b: number, amount: number) => a + (b - a) * amount;
const ease = (value: number) => value * value * (3 - 2 * value);

const sceneNodes = Array.from(document.querySelectorAll<SceneNode>("[data-story-scene]"));
const journey = document.querySelector<HTMLElement>("[data-journey]");
const worldStage = document.querySelector<HTMLElement>("[data-world-stage]");
const canvas = document.querySelector<HTMLCanvasElement>("[data-world-canvas]");
const railYear = document.querySelector<HTMLElement>("[data-rail-year]");
const railChapter = document.querySelector<HTMLElement>("[data-rail-chapter]");
const railFill = document.querySelector<HTMLElement>("[data-rail-fill]");
const coordinates = document.querySelector<HTMLElement>("[data-coordinates]");
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
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const compact = window.matchMedia("(max-width: 720px)").matches;

const points: ScenePoint[] = sceneNodes.map((element) => ({
  id: element.dataset.sceneId,
  order: Number(element.dataset.order),
  title: element.querySelector<HTMLElement>("h2")?.textContent?.trim() ?? "",
  latitude: Number(element.dataset.latitude),
  longitude: Number(element.dataset.longitude),
  x: Number(element.dataset.cameraX),
  y: Number(element.dataset.cameraY),
  scale: Number(element.dataset.cameraScale),
  rotation: Number(element.dataset.cameraRotation),
  side: element.classList.contains("story-scene--right") ? "right" : "left",
  period: element.querySelector<HTMLElement>(".scene-period")?.textContent?.trim() ?? "",
  element,
}));

let activeIndex = -1;
let frameRequested = false;
let sceneCenters: number[] = [];
let app: Application | undefined;
let world: Container | undefined;
let routeActive: Graphics | undefined;
let routeGlow: Graphics | undefined;
let routeFracture: Graphics | undefined;
let routeMarkers: Graphics[] = [];
let mapWidth = 2400;
let mapHeight = 1500;
let insightPinned = false;
let activePlaceKey: string | undefined;
let activePlaceControl: HTMLButtonElement | undefined;
let suppressNextFocusPreview = false;

function formatCoordinate(value: number, positive: string, negative: string) {
  return `${Math.abs(Math.round(value))}° ${value >= 0 ? positive : negative}`;
}

function formatRailYear(period: string) {
  const first = period.split("–")[0]?.trim() ?? period;
  if (/^\d+$/.test(first) && period.includes("BC")) return `${first} BC`;
  return first;
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

function project(point: ScenePoint) {
  return { x: point.x * mapWidth, y: point.y * mapHeight };
}

function projectCoordinates(latitude: number, longitude: number) {
  return {
    x: clamp((longitude + 20) / 85) * mapWidth,
    y: clamp((72 - latitude) / 47) * mapHeight,
  };
}

function getPlaceKey(button: HTMLButtonElement) {
  return `${button.dataset.sceneId}:${button.dataset.hotspotId}`;
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
  if (restoreFocus && controlToRestore && !controlToRestore.hidden) {
    requestAnimationFrame(() => {
      suppressNextFocusPreview = true;
      controlToRestore.focus({ preventScroll: true });
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
}

function updateMobileControls(index: number) {
  const current = points[index];
  for (const button of mobilePlaceButtons) {
    button.hidden = button.dataset.sceneId !== current.id;
  }
  if (mobileSceneCount) {
    mobileSceneCount.textContent = `${String(current.order).padStart(2, "0")} / ${points.length}`;
  }
  if (mobileSceneTitle) mobileSceneTitle.textContent = current.title;
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
  point.element.scrollIntoView({
    behavior: reduceMotion ? "auto" : "smooth",
    block: "start",
  });
  window.history.replaceState(null, "", `#${point.id}`);
}

function updateHotspotPositions() {
  if (!worldStage || activeIndex < 0) return;
  const activeSceneId = points[activeIndex]?.id;
  const stageWidth = worldStage.clientWidth;
  const stageHeight = worldStage.clientHeight;
  const scale = world?.scale.x ?? Math.max(stageWidth / mapWidth, stageHeight / mapHeight);
  const rotation = world?.rotation ?? 0;
  const pivotX = world?.pivot.x ?? mapWidth / 2;
  const pivotY = world?.pivot.y ?? mapHeight / 2;
  const positionX = world?.position.x ?? stageWidth / 2;
  const positionY = world?.position.y ?? stageHeight / 2;
  const cosine = Math.cos(rotation);
  const sine = Math.sin(rotation);
  const safeTop = compact ? 128 : 72;
  const safeBottom = compact ? 100 : 44;
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
      Number(button.dataset.latitude),
      Number(button.dataset.longitude),
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
  if (compact && visibleCandidates.length === 2) {
    const [first, second] = visibleCandidates;
    const distance = Math.hypot(first.screenX - second.screenX, first.screenY - second.screenY);
    if (distance < 58) {
      const midpointX = (first.screenX + second.screenX) / 2;
      const midpointY = (first.screenY + second.screenY) / 2;
      first.screenX = clamp(midpointX - 29, 24, stageWidth - 24);
      first.screenY = clamp(midpointY - 4, safeTop, stageHeight - safeBottom);
      second.screenX = clamp(midpointX + 29, 24, stageWidth - 24);
      second.screenY = clamp(midpointY + 4, safeTop, stageHeight - safeBottom);
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

  const segment = Math.min(points.length - 2, Math.floor(progress));
  const within = clamp(progress - segment);
  const start = project(points[0]);
  routeActive.moveTo(start.x, start.y);
  routeGlow.moveTo(start.x, start.y);

  for (let index = 1; index <= segment + 1; index += 1) {
    const point = project(points[index]);
    routeActive.lineTo(point.x, point.y);
    routeGlow.lineTo(point.x, point.y);
  }

  if (progress < points.length - 1) {
    const from = project(points[segment]);
    const to = project(points[segment + 1]);
    const current = {
      x: lerp(from.x, to.x, within),
      y: lerp(from.y, to.y, within),
    };
    routeActive.lineTo(current.x, current.y);
    routeGlow.lineTo(current.x, current.y);
  }

  routeGlow.stroke({ color: 0xc9964b, width: 13, alpha: 0.16, cap: "round", join: "round" });
  routeActive.stroke({ color: 0xf0c975, width: 3.1, alpha: 0.94, cap: "round", join: "round" });

  if (routeFracture && progress >= 10.65) {
    const fracture = project(points[11]);
    routeFracture
      .moveTo(fracture.x - 14, fracture.y - 14)
      .lineTo(fracture.x + 14, fracture.y + 14)
      .moveTo(fracture.x + 14, fracture.y - 14)
      .lineTo(fracture.x - 14, fracture.y + 14)
      .stroke({ color: 0xb84d3d, width: 3.2, alpha: 0.95, cap: "round" });
  }
}

function setActive(index: number) {
  if (index === activeIndex) return;
  hideInsight();
  activeIndex = index;
  const current = points[index];

  for (const [sceneIndex, scene] of sceneNodes.entries()) {
    const isActive = sceneIndex === index;
    scene.classList.toggle("is-active", isActive);
    if (isActive) scene.setAttribute("aria-current", "step");
    else scene.removeAttribute("aria-current");
  }

  for (const link of railLinks) {
    if (link.dataset.railLink === current.id) link.setAttribute("aria-current", "step");
    else link.removeAttribute("aria-current");
  }

  if (railChapter) railChapter.textContent = String(current.order).padStart(2, "0");
  if (railYear) railYear.textContent = formatRailYear(current.period);
  if (coordinates) {
    coordinates.textContent = `${formatCoordinate(current.latitude, "N", "S")} · ${formatCoordinate(
      current.longitude,
      "E",
      "W",
    )}`;
  }
  document.body.dataset.era = current.element.dataset.palette;
  document.body.dataset.sceneSide = current.side;
  updateMobileControls(index);
  updateHotspotPositions();
}

function updateWorld() {
  frameRequested = false;
  if (!points.length || !journey) return;

  const journeyRect = journey.getBoundingClientRect();
  const journeyActive = journeyRect.top < window.innerHeight * 0.55 && journeyRect.bottom > window.innerHeight * 0.35;
  document.body.classList.toggle("journey-active", journeyActive);

  const rawProgress = locateProgress();
  const index = Math.min(points.length - 1, Math.max(0, Math.round(rawProgress)));
  setActive(index);

  const totalProgress = clamp(rawProgress / (points.length - 1));
  if (railFill) railFill.style.height = `${totalProgress * 100}%`;
  routeMarkers.forEach((marker, markerIndex) => {
    const distance = Math.abs(markerIndex - rawProgress);
    marker.alpha = markerIndex <= rawProgress + 0.35 ? 0.9 : Math.max(0.12, 0.34 - distance * 0.025);
  });

  if (!world || !app || reduceMotion) {
    updateHotspotPositions();
    return;
  }

  if (compact) {
    const current = points[index];
    const baseScale = Math.max(app.screen.width / mapWidth, app.screen.height / mapHeight);
    world.pivot.set(current.x * mapWidth, current.y * mapHeight);
    world.position.set(app.screen.width * 0.5, app.screen.height * 0.52);
    world.scale.set(baseScale * Math.max(1.05, current.scale * 0.82));
    world.rotation = 0;
    drawRoute(index);
    updateHotspotPositions();
    return;
  }

  const fromIndex = Math.min(points.length - 1, Math.floor(rawProgress));
  const toIndex = Math.min(points.length - 1, fromIndex + 1);
  const amount = ease(clamp(rawProgress - fromIndex));
  const from = points[fromIndex];
  const to = points[toIndex];
  const x = lerp(from.x, to.x, amount) * mapWidth;
  const y = lerp(from.y, to.y, amount) * mapHeight;
  const zoom = lerp(from.scale, to.scale, amount);
  const rotation = lerp(from.rotation, to.rotation, amount);
  const baseScale = Math.max(app.screen.width / mapWidth, app.screen.height / mapHeight);
  const focusX = lerp(from.side === "left" ? 0.69 : 0.31, to.side === "left" ? 0.69 : 0.31, amount);

  world.pivot.set(x, y);
  world.position.set(app.screen.width * focusX, app.screen.height * 0.5);
  world.scale.set(baseScale * zoom);
  world.rotation = rotation;
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
    button.addEventListener("click", () => chapterDialog?.showModal());
  });
  closeButton?.addEventListener("click", () => chapterDialog?.close());
  jumpLinks.forEach((link) => link.addEventListener("click", () => chapterDialog?.close()));
  chapterDialog?.addEventListener("click", (event) => {
    if (event.target === chapterDialog) chapterDialog.close();
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

  mobilePreviousButton?.addEventListener("click", () => moveToScene(activeIndex - 1));
  mobileNextButton?.addEventListener("click", () => moveToScene(activeIndex + 1));

  closeInsightButton?.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    window.setTimeout(() => hideInsight(!compact), 0);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !mapInsight?.hidden) hideInsight(!compact);
  });
}

async function setupWorld() {
  if (!worldStage || !canvas || reduceMotion) return;

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
    resolution: Math.min(window.devicePixelRatio, 1.6),
    powerPreference: "high-performance",
  });

  const texture = await Assets.load<Texture>(mapUrl);
  mapWidth = texture.width;
  mapHeight = texture.height;
  world = new Container();
  app.stage.addChild(world);

  const map = new Sprite(texture);
  map.width = mapWidth;
  map.height = mapHeight;
  map.tint = 0xc9b888;
  world.addChild(map);

  const shadow = new Graphics()
    .rect(0, 0, mapWidth, mapHeight)
    .fill({ color: 0x071219, alpha: 0.08 });
  world.addChild(shadow);

  const routeBase = new Graphics();
  const first = project(points[0]);
  routeBase.moveTo(first.x, first.y);
  for (const point of points.slice(1)) {
    const projected = project(point);
    routeBase.lineTo(projected.x, projected.y);
  }
  routeBase.stroke({ color: 0xd7bd82, width: 2, alpha: 0.26, cap: "round", join: "round" });
  world.addChild(routeBase);

  routeGlow = new Graphics();
  world.addChild(routeGlow);
  routeActive = new Graphics();
  world.addChild(routeActive);
  routeFracture = new Graphics();
  world.addChild(routeFracture);

  routeMarkers = [];
  for (const [index, point] of points.entries()) {
    const projected = project(point);
    const marker = new Graphics()
      .circle(projected.x, projected.y, index === 0 ? 7 : 5)
      .fill({ color: 0xf1ca78, alpha: 0.92 })
      .circle(projected.x, projected.y, index === 0 ? 15 : 12)
      .stroke({ color: 0xe8bd68, width: 1.4, alpha: 0.46 });
    routeMarkers.push(marker);
    world.addChild(marker);
  }

  if (landmarkUrl) {
    try {
      const landmarkTexture = await Assets.load<Texture>(landmarkUrl);
      const panorama = new Sprite(landmarkTexture);
      panorama.anchor.set(0.5, 1);
      panorama.position.set(mapWidth * 0.52, mapHeight * 0.97);
      panorama.width = mapWidth * 0.98;
      panorama.height = Math.min(mapHeight * 0.31, panorama.height * (panorama.width / landmarkTexture.width));
      panorama.alpha = 0.26;
      world.addChildAt(panorama, 2);
    } catch {
      // The journey remains complete when the optional atmospheric layer is unavailable.
    }
  }

  document.body.classList.add("world-ready");
  updateCenters();
  requestUpdate();
}

setupControls();
updateCenters();
setActive(0);
requestUpdate();

window.addEventListener("scroll", requestUpdate, { passive: true });
window.addEventListener("resize", () => {
  updateCenters();
  requestUpdate();
});
window.addEventListener("load", () => {
  updateCenters();
  requestUpdate();
});

void setupWorld();
