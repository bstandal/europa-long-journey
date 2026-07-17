export type InteractionFamily = "route" | "network" | "boundary" | "compare";

export type MapScope = "europe" | "world";

export type MapCoordinate = {
  latitude: number;
  longitude: number;
  label?: string;
};

export type InteractionStep = {
  id: string;
  label: string;
  summary: string;
  points: MapCoordinate[];
  links?: [number, number][];
  closed?: boolean;
};

export type StoryInteraction = {
  family: InteractionFamily;
  prompt: string;
  accessibleSummary: string;
  mapScope: MapScope;
  steps: InteractionStep[];
};

export type StoryScene = {
  id: string;
  order: number;
  era: string;
  period: { start: number; end?: number; label: string };
  title: string;
  kicker: string;
  thesis: string;
  body: string;
  focus: { latitude: number; longitude: number };
  camera: { x: number; y: number; scale: number; rotation?: number };
  palette: string;
  layers: string[];
  sourceIds: string[];
  landmark: string;
  side: "left" | "right";
  transitionEffect?: "fracture" | "rebuild" | "return";
  interaction: StoryInteraction;
  hotspots: {
    id: string;
    label: string;
    detail: string;
    latitude: number;
    longitude: number;
  }[];
  chronicle?: { href: string; label: string };
};

export type SourceRecord = {
  id: string;
  author: string;
  title: string;
  publication?: string;
  year: string;
  url?: string;
  note?: string;
};

export type AssetRecord = {
  id: string;
  title: string;
  creator: string;
  institution: string;
  sourceUrl: string;
  license: string;
  requiredCredit: string;
  localPath: string;
};
