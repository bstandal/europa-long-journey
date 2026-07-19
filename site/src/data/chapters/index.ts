import type { ChapterDefinition } from "../../types/chapter";
import { bronzeEurope } from "./bronze-europe";
import { empireTakesCross } from "./empire-takes-cross";
import { firstFarmers } from "./first-farmers";
import { greeceAndTheCitizen } from "./greece-and-the-citizen";
import { romeGathersEurope } from "./rome-gathers-europe";
import { steppeComesWest } from "./steppe-comes-west";

export const chapters: ChapterDefinition[] = [
  firstFarmers,
  steppeComesWest,
  bronzeEurope,
  greeceAndTheCitizen,
  romeGathersEurope,
  empireTakesCross,
];

export const chapterBySlug = new Map(chapters.map((chapter) => [chapter.slug, chapter]));
