import { useCallback, useEffect, useRef } from "react";
export function useEngine() {
  const worker = useRef<Worker | null>(null),
    pending = useRef(
      new Map<
        number,
        { resolve: (value: any) => void; reject: (error: Error) => void }
      >(),
    ),
    serial = useRef(0);
  const stop = useCallback(() => {
    worker.current?.terminate();
    worker.current = null;
    for (const p of pending.current.values()) p.reject(new Error("Cancelled"));
    pending.current.clear();
  }, []);
  useEffect(() => stop, [stop]);
  const run = useCallback(
    (data: Record<string, unknown>) =>
      new Promise<any>((resolve, reject) => {
        if (!worker.current) {
          worker.current = new Worker(
            new URL("./engine.worker.ts", import.meta.url),
            { type: "module" },
          );
          worker.current.onmessage = (e) => {
            const p = pending.current.get(e.data.id);
            if (p) {
              pending.current.delete(e.data.id);
              e.data.error
                ? p.reject(new Error(e.data.error))
                : p.resolve(e.data);
            }
          };
          worker.current.onerror = () => {
            stop();
          };
        }
        const id = ++serial.current;
        pending.current.set(id, { resolve, reject });
        worker.current.postMessage({ ...data, id });
      }),
    [stop],
  );
  return { run, stop };
}
