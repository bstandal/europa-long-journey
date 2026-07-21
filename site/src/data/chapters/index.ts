import type { ChapterDefinition } from "../../types/chapter";
import { bronzeEurope } from "./bronze-europe";
import { empireManyLiberties } from "./empire-many-liberties";
import { empireTakesCross } from "./empire-takes-cross";
import { europeHoldsTheLine } from "./europe-holds-the-line";
import { europeReborn } from "./europe-reborn";
import { europeTurnsSeaward } from "./europe-turns-seaward";
import { firstFarmers } from "./first-farmers";
import { greeceAndTheCitizen } from "./greece-and-the-citizen";
import { hanseaticNorth } from "./hanseatic-north";
import { medievalCommercialRevolution } from "./medieval-commercial-revolution";
import { papalRevolution } from "./papal-revolution";
import { romeGathersEurope } from "./rome-gathers-europe";
import { societyBeyondKin } from "./society-beyond-kin";
import { steppeComesWest } from "./steppe-comes-west";

export const chapters: ChapterDefinition[] = [
  firstFarmers,
  steppeComesWest,
  bronzeEurope,
  greeceAndTheCitizen,
  romeGathersEurope,
  empireTakesCross,
  europeReborn,
  papalRevolution,
  societyBeyondKin,
  medievalCommercialRevolution,
  hanseaticNorth,
  empireManyLiberties,
  europeHoldsTheLine,
  europeTurnsSeaward,
];

export const chapterBySlug = new Map(
  chapters.map((chapter) => [chapter.slug, chapter]),
);
