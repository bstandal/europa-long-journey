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

export type ChapterStageState = {
  id: string;
  label: string;
  detail: string;
  stageImage?: string;
  mobileStageImage?: string;
  overlayImage?: string;
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

export type MobilityInteraction = ChapterInteractionBase & {
  kind: "mobility";
  states: {
    id: string;
    label: string;
    detail: string;
    reach: string;
    load: string;
  }[];
};

export type TurnoverInteraction = ChapterInteractionBase & {
  kind: "turnover";
  regions: {
    id: string;
    label: string;
    period: string;
    detail: string;
    measures: {
      id: "ancestry" | "local-paternal" | "incoming-paternal";
      label: string;
      value: string;
      note: string;
    }[];
    sourceId: string;
  }[];
};

export type InheritanceInteraction = ChapterInteractionBase & {
  kind: "inheritance";
  mapImage: string;
  layers: {
    id: "people" | "language" | "religion";
    label: string;
    detail: string;
    routes: {
      id: string;
      label: string;
      points: { x: number; y: number }[];
    }[];
    correspondences?: {
      reconstructed: string;
      west: string;
      east: string;
      note: string;
    }[];
  }[];
};

export type InscriptionInteraction = ChapterInteractionBase & {
  kind: "inscription";
  states: (ChapterStageState & {
    mode: "surface" | "reading" | "consequence";
    heading: string;
    excerpt?: string;
    annotation: string;
  })[];
};

export type CitizenBodyInteraction = ChapterInteractionBase & {
  kind: "citizen-body";
  mapImage: string;
  states: (ChapterStageState & {
    overlayImage: string;
    measure: string;
  })[];
};

export type CivicPathInteraction = ChapterInteractionBase & {
  kind: "civic-path";
  paths: {
    id: "council" | "jury" | "assembly";
    label: string;
    role: string;
    detail: string;
    steps: {
      id: string;
      label: string;
      detail: string;
    }[];
    result: string;
  }[];
};

export type WarTimelineInteraction = ChapterInteractionBase & {
  kind: "war-timeline";
  mapImage: string;
  states: (ChapterStageState & {
    period: string;
    overlayImage: string;
    athens: string;
    sparta: string;
    turningPoint: string;
  })[];
};

export type RomanConstitutionInteraction = ChapterInteractionBase & {
  kind: "roman-constitution";
  institutions: {
    id: "people" | "magistrates" | "senate";
    label: string;
    detail: string;
    authority: string;
    limit: string;
    consequence: string;
  }[];
};

export type RomanNetworkInteraction = ChapterInteractionBase & {
  kind: "roman-network";
  mapImage: string;
  states: {
    id: string;
    label: string;
    period: string;
    detail: string;
    measure: string;
    points: ChapterPoint[];
    links: [number, number][];
  }[];
};

export type RomanCommandInteraction = ChapterInteractionBase & {
  kind: "roman-command";
  states: {
    id: string;
    label: string;
    period: string;
    detail: string;
    commander: string;
    command: string;
    institutionalChange: string;
  }[];
};

export type RomanCitizenshipInteraction = ChapterInteractionBase & {
  kind: "roman-citizenship";
  paths: {
    id: string;
    label: string;
    detail: string;
    startingStatus: string;
    route: string;
    rights: string;
    limit: string;
  }[];
};

export type RomanTraceInteraction = ChapterInteractionBase & {
  kind: "roman-trace";
  stops: {
    id: string;
    label: string;
    period: string;
    detail: string;
    mechanism: string;
    consequence: string;
  }[];
};

export type ChristianPolicyInteraction = ChapterInteractionBase & {
  kind: "christian-policy";
  states: {
    id: string;
    label: string;
    period: string;
    detail: string;
    imperialAction: string;
    churchPosition: string;
    publicSign: string;
  }[];
};

export type ChristianCouncilInteraction = ChapterInteractionBase & {
  kind: "christian-council";
  states: {
    id: string;
    label: string;
    period: string;
    detail: string;
    authority: string;
    act: string;
    consequence: string;
  }[];
};

export type ChristianCityInteraction = ChapterInteractionBase & {
  kind: "christian-city";
  mapImage: string;
  states: {
    id: string;
    label: string;
    period: string;
    detail: string;
    reach: string;
    institution: string;
    inheritance: string;
  }[];
};

export type SacredSpaceInteraction = ChapterInteractionBase & {
  kind: "sacred-space";
  states: {
    id: string;
    label: string;
    period: string;
    detail: string;
    challenge: string;
    answer: string;
    consequence: string;
  }[];
};

export type ChristianTraceInteraction = ChapterInteractionBase & {
  kind: "christian-trace";
  stops: {
    id: string;
    label: string;
    period: string;
    detail: string;
    instrument: string;
    inheritance: string;
  }[];
};

export type CommonwealthCityInteraction = ChapterInteractionBase & {
  kind: "commonwealth-city";
  states: {
    id: string;
    label: string;
    period: string;
    detail: string;
    office: string;
    instrument: string;
    limit: string;
  }[];
};

export type WrittenNetworkInteraction = ChapterInteractionBase & {
  kind: "written-network";
  states: {
    id: string;
    label: string;
    period: string;
    detail: string;
    author: string;
    carrier: string;
    localAct: string;
  }[];
};

export type RealmPartitionInteraction = ChapterInteractionBase & {
  kind: "realm-partition";
  states: {
    id: string;
    label: string;
    period: string;
    detail: string;
    share: string;
    basis: string;
    consequence: string;
  }[];
};

export type ConversionRoadsInteraction = ChapterInteractionBase & {
  kind: "conversion-roads";
  paths: {
    id: string;
    label: string;
    period: string;
    detail: string;
    patron: string;
    language: string;
    institution: string;
    limit: string;
  }[];
};

export type CommonwealthTraceInteraction = ChapterInteractionBase & {
  kind: "commonwealth-trace";
  stops: {
    id: string;
    label: string;
    period: string;
    detail: string;
    instrument: string;
    reach: string;
    inheritance: string;
  }[];
};

export type ChapterInteraction =
  | RouteInteraction
  | SeasonsInteraction
  | HarvestInteraction
  | InspectInteraction
  | LineageInteraction
  | GrowthInteraction
  | CompareInteraction
  | MobilityInteraction
  | TurnoverInteraction
  | InheritanceInteraction
  | InscriptionInteraction
  | CitizenBodyInteraction
  | CivicPathInteraction
  | WarTimelineInteraction
  | RomanConstitutionInteraction
  | RomanNetworkInteraction
  | RomanCommandInteraction
  | RomanCitizenshipInteraction
  | RomanTraceInteraction
  | ChristianPolicyInteraction
  | ChristianCouncilInteraction
  | ChristianCityInteraction
  | SacredSpaceInteraction
  | ChristianTraceInteraction
  | CommonwealthCityInteraction
  | WrittenNetworkInteraction
  | RealmPartitionInteraction
  | ConversionRoadsInteraction
  | CommonwealthTraceInteraction;

export type ChapterTheme = {
  id:
    | "farmers"
    | "steppe"
    | "bronze"
    | "greece"
    | "rome"
    | "christian"
    | "carolingian";
  label: string;
};

export type ChapterAct = {
  id: string;
  number: string;
  label: string;
  period: string;
  title: string;
  detail: string;
};

export type ChapterEnding = {
  period: string;
  title: string;
  detail: string;
  image?: string;
  mobileImage?: string;
  nextPeriod: string;
};

export type ChapterMovement = {
  id: string;
  actId?: string;
  order: number;
  period: string;
  place: string;
  title: string;
  titleLines?: string[];
  thesis: string;
  body: string[];
  image: string;
  mobileImage?: string;
  imageAlt: string;
  imagePosition?: string;
  mobileImagePosition?: string;
  visualTone?: string;
  side: "left" | "right";
  sourceIds: string[];
  evidence: string[];
  map: {
    x: number;
    y: number;
  };
  interaction?: ChapterInteraction;
};

export type ChapterDefinition = {
  slug: string;
  number: string;
  title: string;
  period: string;
  claim: string;
  theme: ChapterTheme;
  openingAction: string;
  mapLabel: string;
  routeImage?: string;
  openingRouteImage?: string;
  sourcesEyebrow: string;
  ending: ChapterEnding;
  returnHash: string;
  nextHash: string;
  nextTitle: string;
  acts?: ChapterAct[];
  movements: ChapterMovement[];
};
