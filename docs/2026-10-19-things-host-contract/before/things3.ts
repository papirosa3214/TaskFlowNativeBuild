import { execFile } from "node:child_process";
import os from "node:os";
import { BadArgsError, type OperationContext, requireString } from "./types.js";

/**
 * Things3 для роли, которая крутится на .110.
 *
 * Зачем: Things3 — macOS-приложение, роль на сервере к нему не достаётся ни
 * как. Но хост на маке уже умеет отвечать на операции шлюза, и логика доступа
 * к Things3 уже написана один раз — `things_mcp_server.py`. Вторая копия
 * была бы дублированием, которое рано или поздно разойдётся с оригиналом,
 * поэтому операция зовёт именно его.
 *
 * Что отдаём наружу: `{ tool, arguments }` — тем же словами, что и сам MCP,
 * чтобы описание инструмента у роли и у скрипта не расходились.
 */

/** Инструменты `things_mcp_server.TOOLS` — на 18.10.2026 ровно эти. */
export const ДОСТУПНЫЕ_ИНСТРУМЕНТЫ = [
  "things_today",
  "things_inbox",
  "things_upcoming",
  "things_anytime",
  "things_someday",
  "things_search",
  "things_projects",
  "things_areas",
  "things_add",
  "things_complete",
  "things_show",
] as const;

export type ThingsTool = (typeof ДОСТУПНЫЕ_ИНСТРУМЕНТЫ)[number];

/** Имя приходит от модели — проверяем по списку, а не по регулярке. */
export function проверитьИмя(имя: string): ThingsTool {
  if (!(ДОСТУПНЫЕ_ИНСТРУМЕНТЫ as readonly string[]).includes(имя)) {
    throw new BadArgsError(
      `«${имя}» — не инструмент Things3. Доступны: ${ДОСТУПНЫЕ_ИНСТРУМЕНТЫ.join(", ")}`,
    );
  }
  return имя as ThingsTool;
}

const СКРИПТ = "~/.hermes/scripts/things_mcp_server.py";
const PYTHON = "~/.hermes/mcp/.venv/bin/python3";

/**
 * Мост к скрипту. Отдельная функция, а не прямое `execFile` внутри
 * операции: тест подставляет заглушку и не трогает живой Things3 (решение
 * владельца 18.10.2026), а в бою подставляется настоящий вызов.
 */
export type Исполнитель = (
  запрос: { tool: string; arguments: Record<string, unknown> },
) => Promise<string>;

const развернуть = (путь: string): string => (путь.startsWith("~") ? путь.replace("~", os.homedir()) : путь);

/**
 * Вызывает скрипт как MCP-сервер и достаёт ответ на `tools/call`.
 *
 * Через настоящий протокол, а не через внутреннюю функцию скрипта: иначе
 * придётся дублировать его разбор аргументов, а он может разойтись с тем,
 * что реально отвечает клиенту.
 */
export const вызватьСкрипт: Исполнитель = async ({ tool, arguments: аргументы }) =>
  new Promise<string>((resolve, reject) => {
    const запросы = [
      {
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {
          protocolVersion: "2024-11-05",
          capabilities: {},
          clientInfo: { name: "taskflow-host", version: "1.0.0" },
        },
      },
      { jsonrpc: "2.0", method: "notifications/initialized", params: {} },
      {
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: { name: tool, arguments: аргументы },
      },
    ].map((сообщение) => JSON.stringify(сообщение) + "\n").join("");

    const child = execFile(
      развернуть(PYTHON),
      [развернуть(СКРИПТ)],
      { encoding: "utf8", timeout: 60_000, maxBuffer: 4 * 1024 * 1024 },
      (ошибка, stdout, stderr) => {
        if (ошибка && !stdout) {
          reject(new Error(`Things3 недоступен: ${(stderr || ошибка.message).trim().split("\n")[0]}`));
          return;
        }
        const строки = stdout.split("\n").filter(Boolean);
        for (let i = строки.length - 1; i >= 0; i -= 1) {
          let сообщение: any;
          try {
            сообщение = JSON.parse(строки[i]!);
          } catch {
            continue;
          }
          if (сообщение?.id === 2) {
            if (сообщение.error) {
              reject(new Error(`Things3 вернул ошибку: ${сообщение.error.message ?? JSON.stringify(сообщение.error)}`));
              return;
            }
            resolve(
              (сообщение.result?.content ?? [])
                .map((часть: any) => (typeof часть?.text === "string" ? часть.text : ""))
                .join("\n"),
            );
            return;
          }
        }
        reject(new Error("Things3 не ответил на вызов"));
      },
    );
    child.stdin?.end(запросы);
  });

export interface Things3Result {
  tool: string;
  arguments: Record<string, unknown>;
  ok: boolean;
  result: string;
}

export const things3 = async (
  args: Record<string, unknown>,
  _context: OperationContext,
  исполнитель: Исполнитель = вызватьСкрипт,
): Promise<Things3Result> => {
  const tool = проверитьИмя(requireString(args, "tool"));

  const сырые = args.arguments;
  let аргументы: Record<string, unknown>;
  if (сырые === undefined || сырые === null) {
    аргументы = {};
  } else if (typeof сырые === "object" && !Array.isArray(сырые)) {
    аргументы = сырые as Record<string, unknown>;
  } else {
    // Строка или число сюда не дойдут: скрипт сам разберётся и молча
    // сделает не то, что роль имела в виду.
    throw new BadArgsError("«arguments» должен быть объектом");
  }

  const result = await исполнитель({ tool, arguments: аргументы });

  return {
    tool,
    arguments: аргументы,
    ok: true,
    // Пустой ответ — тоже ответ. Молчание выглядело бы как «ничего не нашлось»,
    // и роль решила бы, что список пуст, а не что скрипт не отвечает.
    result: result.trim() || "(Things3 вернул пустой ответ)",
  };
};

export const things3OpName = "things3";