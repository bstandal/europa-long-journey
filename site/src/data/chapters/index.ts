import type { ChapterDefinition } from "../../types/chapter";
import { bronzeEurope } from "./bronze-europe";
import { continentRebuilt } from "./continent-rebuilt";
import { dutchRepublic } from "./dutch-republic";
import { empireManyLiberties } from "./empire-many-liberties";
import { empireTakesCross } from "./empire-takes-cross";
import { enlightenmentPublicOpinion } from "./enlightenment-public-opinion";
import { europeHoldsTheLine } from "./europe-holds-the-line";
import { europeReborn } from "./europe-reborn";
import { europeAtWar } from "./europe-at-war";
import { europeReturns } from "./europe-returns";
import { europeTurnsSeaward } from "./europe-turns-seaward";
import { europeanWorld } from "./european-world";
import { firstFarmers } from "./first-farmers";
import { greeceAndTheCitizen } from "./greece-and-the-citizen";
import { habsburgEurope } from "./habsburg-europe";
import { hanseaticNorth } from "./hanseatic-north";
import { medievalCommercialRevolution } from "./medieval-commercial-revolution";
import { papalRevolution } from "./papal-revolution";
import { reformation } from "./reformation";
import { rivalryIndustrialBreakthrough } from "./rivalry-industrial-breakthrough";
import { romeGathersEurope } from "./rome-gathers-europe";
import { scientificRevolution } from "./scientific-revolution";
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
  reformation,
  habsburgEurope,
  scientificRevolution,
  dutchRepublic,
  enlightenmentPublicOpinion,
  rivalryIndustrialBreakthrough,
  europeanWorld,
  europeAtWar,
  continentRebuilt,
  europeReturns,
];

export const chapterBySlug = new Map(
  chapters.map((chapter) => [chapter.slug, chapter]),
);
