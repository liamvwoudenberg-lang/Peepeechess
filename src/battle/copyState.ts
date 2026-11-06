/** Battle snapshots and bindings contain JSON data only; older WebViews can copy them too. */
export function copyState<T>(value: T): T {
  return typeof globalThis.structuredClone === "function"
    ? globalThis.structuredClone(value)
    : JSON.parse(JSON.stringify(value));
}
