const SEOUL_TZ = "Asia/Seoul";

export function todaySeoul(): string {
  return formatDateSeoul(new Date());
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function formatDateSeoul(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: SEOUL_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(date);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

export function seoulWeekday(dateString = todaySeoul()): number {
  const date = new Date(`${dateString}T00:00:00+09:00`);
  return (date.getDay() + 6) % 7;
}

export function displayDate(dateString: string): string {
  const date = new Date(`${dateString}T00:00:00+09:00`);
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: SEOUL_TZ,
    month: "long",
    day: "numeric",
    weekday: "short"
  }).format(date);
}

export function addDays(dateString: string, days: number): string {
  const date = new Date(`${dateString}T00:00:00+09:00`);
  date.setDate(date.getDate() + days);
  return formatDateSeoul(date);
}

export function monthKey(dateString = todaySeoul()): string {
  return dateString.slice(0, 7);
}

export function formatTime(value?: string | null): string {
  if (!value) return "";
  return value.slice(0, 5);
}

export function formatKrw(value: number): string {
  return new Intl.NumberFormat("ko-KR").format(value);
}

export function relativeHours(value?: string | null): number | null {
  if (!value) return null;
  const at = new Date(value).getTime();
  if (Number.isNaN(at)) return null;
  return (Date.now() - at) / 36e5;
}
