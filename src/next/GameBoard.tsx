import React, { lazy, Suspense, useEffect, useRef, useState } from "react";
import { Board } from "./Board";
import type { Army, ArenaStyle } from "../game/battleProfiles";
const Scene = lazy(() => import("./Scene"));
class SceneBoundary extends React.Component<
  { children: React.ReactNode; onFail: () => void },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch() {
    this.props.onFail();
  }
  render() {
    return this.state.failed ? null : this.props.children;
  }
}
type Props = React.ComponentProps<typeof Board> & {
  view: "2d" | "3d";
  models: boolean;
  allowSlow: boolean;
  competitive: boolean;
  arena: ArenaStyle;
  armies: { w: Army; b: Army };
  onSceneFail: () => void;
};
export function GameBoard({
  view,
  models,
  allowSlow,
  competitive,
  onSceneFail,
  ...board
}: Props) {
  const [failed, setFailed] = useState(false),
    [ready, setReady] = useState(false);
  const failRef = useRef(onSceneFail);
  failRef.current = onSceneFail;
  useEffect(() => {
    setFailed(false);
    setReady(false);
  }, [models, view]);
  const active = models && view === "3d" && !failed;
  const fail = () => {
    setFailed(true);
    setReady(false);
    if (view === "3d") failRef.current();
  };
  return (
    <div
      className={`miniature-board ${active && ready ? "model-active" : ""} camera-${view === "2d" ? "illustrated" : "castle"}`}
      data-renderer={active && ready ? "models" : "atlas"}
    >
      <div className="model-input">
        <Board
          {...board}
          animationMode={active && ready ? "off" : board.animationMode}
          sound={active && ready ? false : board.sound}
        />
      </div>
      {active && (
        <SceneBoundary key={`${models}-${view}-${failed}`} onFail={fail}>
          <Suspense fallback={null}>
            <Scene
              fen={board.fen}
              lastMove={board.lastMove}
              orientation={board.orientation}
              armies={board.armies}
              arena={board.arena}
              view="angled"
              animationMode={board.animationMode || "brief"}
              reducedMotion={Boolean(board.reducedMotion)}
              sound={Boolean(board.sound)}
              competitive={competitive}
              allowSlow={allowSlow}
              selected={board.selected}
              legal={board.legal}
              onSelect={board.onSelect}
              onFail={fail}
              onReady={() => setReady(true)}
            />
          </Suspense>
        </SceneBoundary>
      )}
    </div>
  );
}
