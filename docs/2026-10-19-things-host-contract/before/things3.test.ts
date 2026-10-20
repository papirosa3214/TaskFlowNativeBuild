import { describe, it, expect, vi } from "vitest";
import { makeContext } from "./helpers.js";
import { ДОСТУПНЫЕ_ИНСТРУМЕНТЫ, things3, проверитьИмя } from "../src/operations/things3.js";

/**
 * Операция things3: мост к Things3 через уже существующий
 * things_mcp_server.py. Роль на .110 не может ходить в macOS-приложение
 * сама — она просит хост, а тот уже умеет.
 *
 * Тесты НЕ трогают живой Things3 (решение владельца 18.10.2026): проверяем
 * разбор аргументов, белый список имён и вызов исполнителя, который
 * подставляется снаружи.
 */

describe("things3: белый список инструментов", () => {
  it("отклоняет имя, которого нет в things_mcp_server", () => {
    expect(() => проверитьИмя("things_hack")).toThrow();
    expect(() => проверитьИмя("rm -rf /")).toThrow();
    expect(() => проверитьИмя("")).toThrow();
  });

  it("принимает реальные инструменты Things3", () => {
    for (const имя of ["things_today", "things_inbox", "things_add", "things_complete"]) {
      expect(проверитьИмя(имя)).toBe(имя);
    }
  });

  it("список инструментов непустой и совпадает с проверяемым", () => {
    expect(ДОСТУПНЫЕ_ИНСТРУМЕНТЫ.length).toBeGreaterThan(0);
    for (const имя of ДОСТУПНЫЕ_ИНСТРУМЕНТЫ) expect(проверитьИмя(имя)).toBe(имя);
  });
});

/**
 * Заглушка исполнителя. Параметр объявлен явно: у `vi.fn(() => …)` без
 * параметров `mock.calls` имеет тип пустого кортежа, и обращение к
 * `calls[0][0]` не проходит типизацию — ровно та ошибка, ради которой
 * операция и вынесена в отдельную функцию.
 */
const заглушка = (ответ: string) =>
  vi.fn(async (_запрос: { tool: string; arguments: Record<string, unknown> }) => ответ);

describe("things3: разбор аргументов", () => {
  it("требует указать инструмент", async () => {
    await expect(things3({ args: {} }, makeContext(), заглушка("ok"))).rejects.toThrow();
  });

  it("не даёт arguments быть строкой или числом", async () => {
    await expect(
      things3({ tool: "things_inbox", arguments: "всё" }, makeContext(), заглушка("ok")),
    ).rejects.toThrow();
    await expect(
      things3({ tool: "things_inbox", arguments: 42 }, makeContext(), заглушка("ok")),
    ).rejects.toThrow();
  });

  it("отдаёт исполнителю ровно tool и arguments", async () => {
    const вызов = заглушка(JSON.stringify([{ title: "купить хлеб" }]));
    const r = (await things3(
      { tool: "things_today", arguments: { any: true } },
      makeContext(),
      вызов,
    )) as { tool: string; arguments: Record<string, unknown>; ok: boolean; result: string };

    expect(вызов).toHaveBeenCalledTimes(1);
    expect(вызов.mock.calls[0]![0]).toEqual({ tool: "things_today", arguments: { any: true } });
    expect(r.tool).toBe("things_today");
    expect(r.ok).toBe(true);
    expect(r.result).toContain("хлеб");
  });

  it("пустые arguments допустимы — things_inbox не требует полей", async () => {
    const вызов = заглушка("[]");
    const r = (await things3({ tool: "things_inbox" }, makeContext(), вызов)) as { ok: boolean };
    expect(вызов.mock.calls[0]![0]).toEqual({ tool: "things_inbox", arguments: {} });
    expect(r.ok).toBe(true);
  });
});

describe("things3: ошибка исполнителя не теряется", () => {
  it("ошибка Python-стороны приходит в текст результата", async () => {
    const вызов = vi.fn(async (_запрос: { tool: string; arguments: Record<string, unknown> }) => {
      throw new Error("Things3 не отвечает (osascript: -1743)");
    });
    await expect(
      things3({ tool: "things_today" }, makeContext(), вызов),
    ).rejects.toThrow(/Things3 не отвечает/);
  });

  it("пустой вывод — не молчание, а внятный ответ", async () => {
    const вызов = заглушка("");
    const r = (await things3({ tool: "things_today" }, makeContext(), вызов)) as {
      ok: boolean;
      result: string;
    };
    expect(r.result.length).toBeGreaterThan(0);
  });
});