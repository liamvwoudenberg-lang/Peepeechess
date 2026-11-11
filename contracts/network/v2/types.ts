/** Native board-world ENet protocol; old v1 clients remain explicitly legacy. */
import type * as Legacy from '../v1/types';
import type { BoardVersion } from '../../v2/types';
export const PROTOCOL = 'peepeechess-enet-v2' as const;
type Version<T> = Omit<BoardVersion<T>, 'protocol'> & { protocol: typeof PROTOCOL };
export type Hello = Version<Legacy.Hello>;
export type Welcome = Version<Legacy.Welcome>;
export type CreateMatch = BoardVersion<Legacy.CreateMatch>;
export type JoinMatch = BoardVersion<Legacy.JoinMatch>;
export type MatchCommand = BoardVersion<Legacy.MatchCommand>;
export type MatchFrame = BoardVersion<Legacy.MatchFrame>;
export type ClockSync = BoardVersion<Legacy.ClockSync>;
export type Ack = BoardVersion<Legacy.Ack>;
