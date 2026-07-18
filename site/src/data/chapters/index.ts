import type { ChapterDefinition } from "../../types/chapter";
import { firstFarmers } from "./first-farmers";

export const chapters: ChapterDefinition[] = [firstFarmers];

export const chapterBySlug = new Map(chapters.map((chapter) => [chapter.slug, chapter]));
