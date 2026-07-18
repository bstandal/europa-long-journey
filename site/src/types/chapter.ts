export type ChapterPoint = {
  id: string;
  label: string;
  detail: string;
  x: number;
  y: number;
};

type ChapterInteractionBase = {
  prompt: string;
  accessibleSummary: string;
};

export type RouteInteraction = ChapterInteractionBase & {
  kind: "route";
  points: ChapterPoint[];
};

export type SeasonsInteraction = ChapterInteractionBase & {
  kind: "seasons";
  initialIndex?: number;
  stages: {
    id: string;
    label: string;
    detail: string;
    landscape: string;
    resources: string[];
    tone: "spring" | "summer" | "autumn" | "winter";
  }[];
};

export type HarvestInteraction = ChapterInteractionBase & {
  kind: "harvest";
  total: number;
  allocations: {
    id: "food" | "reserve" | "seed";
    label: string;
    detail: string;
    initial: number;
    minimum: number;
  }[];
};

export type InspectInteraction = ChapterInteractionBase & {
  kind: "inspect";
  items: ChapterPoint[];
};

export type LineageInteraction = ChapterInteractionBase & {
  kind: "lineage";
  snapshots: {
    id: string;
    label: string;
    period: string;
    detail: string;
    evidence: string;
  }[];
};

export type GrowthInteraction = ChapterInteractionBase & {
  kind: "growth";
  stages: {
    id: string;
    label: string;
    detail: string;
    settlement: string;
    landscape: string;
    image: string;
  }[];
};

export type CompareInteraction = ChapterInteractionBase & {
  kind: "compare";
  before: {
    label: string;
    period: string;
    image: string;
  };
  after: {
    label: string;
    period: string;
    image: string;
  };
  layers: {
    id: string;
    label: string;
    detail: string;
  }[];
};

export type ChapterInteraction =
  | RouteInteraction
  | SeasonsInteraction
  | HarvestInteraction
  | InspectInteraction
  | LineageInteraction
  | GrowthInteraction
  | CompareInteraction;

export type ChapterMovement = {
  id: string;
  order: number;
  period: string;
  place: string;
  title: string;
  titleLines?: string[];
  thesis: string;
  body: string[];
  image: string;
  imageAlt: string;
  imagePosition?: string;
  side: "left" | "right";
  sourceIds: string[];
  evidence: string[];
  map: {
    x: number;
    y: number;
  };
  interaction: ChapterInteraction;
};

export type ChapterDefinition = {
  slug: string;
  number: string;
  title: string;
  period: string;
  claim: string;
  returnHash: string;
  nextHash: string;
  nextTitle: string;
  movements: ChapterMovement[];
};
