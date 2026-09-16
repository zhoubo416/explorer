export type MemoryType =
  | "event"
  | "decision"
  | "reflection"
  | "achievement"
  | "failure"
  | "emotion"
  | "thought";

export type MemoryResult = {
  type: MemoryType;
  content: string;
  summary?: string;
  importance: number;
  emotion?: string;
} | null;

export type GoalResult = {
  title: string;
  description: string;
  success_definition: string;
} | null;

export type GoalUpdateResult = {
  done_actions: string[];
  advance_stage: boolean;
  goal_completed: boolean;
  note: string;
} | null;

export type GoalStatus = "exploring" | "active" | "blocked" | "paused" | "completed" | "archived";

export type GoalStatusUpdateResult = {
  status: GoalStatus;
  note: string;
} | null;

export type ModelResult = {
  reply: string;
  memory: MemoryResult;
  goal: GoalResult;
  goal_update: GoalUpdateResult;
  goal_status_update: GoalStatusUpdateResult;
};

const ALLOWED_TYPES: readonly string[] = [
  "event",
  "decision",
  "reflection",
  "achievement",
  "failure",
  "emotion",
  "thought",
];

const ALLOWED_STATUSES: readonly string[] = [
  "exploring",
  "active",
  "blocked",
  "paused",
  "completed",
  "archived",
];

const clampImportance = (value: unknown): number => {
  const parsed =
    typeof value === "number" ? value : Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.min(100, Math.round(parsed)));
};

export const normalizeMemory = (value: unknown): MemoryResult => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const type = ALLOWED_TYPES.includes(String(raw.type)) ? (raw.type as MemoryType) : null;
  const content = typeof raw.content === "string" ? raw.content.trim() : "";
  if (!type || !content) return null;
  return {
    type,
    content,
    summary:
      typeof raw.summary === "string" && raw.summary.trim()
        ? raw.summary.trim()
        : undefined,
    importance: clampImportance(raw.importance),
    emotion:
      typeof raw.emotion === "string" && raw.emotion.trim()
        ? raw.emotion.trim()
        : undefined,
  };
};

export const normalizeGoal = (value: unknown): GoalResult => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const title = typeof raw.title === "string" ? raw.title.trim() : "";
  if (!title) return null;
  return {
    title,
    description: typeof raw.description === "string" ? raw.description.trim() : "",
    success_definition: typeof raw.success_definition === "string" ? raw.success_definition.trim() : "",
  };
};

export const normalizeGoalUpdate = (value: unknown): GoalUpdateResult => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const doneActions = Array.isArray(raw.done_actions)
    ? raw.done_actions.filter((x) => typeof x === "string").map((x) => String(x).trim()).filter(Boolean)
    : [];
  const note = typeof raw.note === "string" ? raw.note.trim() : "";
  if (!doneActions.length && raw.advance_stage !== true && raw.goal_completed !== true && !note) {
    return null;
  }
  return {
    done_actions: doneActions,
    advance_stage: raw.advance_stage === true,
    goal_completed: raw.goal_completed === true,
    note,
  };
};

export const normalizeGoalStatusUpdate = (value: unknown): GoalStatusUpdateResult => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const status = ALLOWED_STATUSES.includes(String(raw.status)) ? (raw.status as GoalStatus) : null;
  const note = typeof raw.note === "string" ? raw.note.trim() : "";
  if (!status) return null;
  return { status, note };
};

export const parseModelResult = (raw: string): ModelResult => {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)\s*```/i)?.[1] ?? raw;
  const start = fenced.indexOf("{");
  const end = fenced.lastIndexOf("}");
  if (start < 0 || end <= start) return { reply: raw.trim(), memory: null, goal: null, goal_update: null, goal_status_update: null };

  try {
    const parsed = JSON.parse(fenced.slice(start, end + 1));
    const reply = typeof parsed.reply === "string" ? parsed.reply.trim() : "";
    if (!reply) return { reply: raw.trim(), memory: null, goal: null, goal_update: null, goal_status_update: null };
    return {
      reply,
      memory: normalizeMemory(parsed.memory),
      goal: normalizeGoal(parsed.goal),
      goal_update: normalizeGoalUpdate(parsed.goal_update),
      goal_status_update: normalizeGoalStatusUpdate(parsed.goal_status_update),
    };
  } catch {
    return { reply: raw.trim(), memory: null, goal: null, goal_update: null, goal_status_update: null };
  }
};
