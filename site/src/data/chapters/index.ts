import type { ChapterDefinition } from "../../types/chapter";
import { firstFarmers } from "./first-farmers";
import { steppeComesWest } from "./steppe-comes-west";

export const chapters: ChapterDefinition[] = [firstFarmers, steppeComesWest];

export const chapterBySlug = new Map(chapters.map((chapter) => [chapter.slug, chapter]));
