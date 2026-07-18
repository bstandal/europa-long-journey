import type { ChapterDefinition } from "../../types/chapter";
import { bronzeEurope } from "./bronze-europe";
import { firstFarmers } from "./first-farmers";
import { steppeComesWest } from "./steppe-comes-west";

export const chapters: ChapterDefinition[] = [
  firstFarmers,
  steppeComesWest,
  bronzeEurope,
];

export const chapterBySlug = new Map(chapters.map((chapter) => [chapter.slug, chapter]));
