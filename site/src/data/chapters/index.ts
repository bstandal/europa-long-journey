import type { ChapterDefinition } from "../../types/chapter";
import { bronzeEurope } from "./bronze-europe";
import { empireTakesCross } from "./empire-takes-cross";
import { europeReborn } from "./europe-reborn";
import { firstFarmers } from "./first-farmers";
import { greeceAndTheCitizen } from "./greece-and-the-citizen";
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
];

export const chapterBySlug = new Map(chapters.map((chapter) => [chapter.slug, chapter]));
