import { ClanClub, LeagueDivision, MatchEmote } from '../types/chess';

export const MEDIEVAL_MATCH_EMOTES: MatchEmote[] = [
  { id: 'emote_salute', name: 'Knight Salute', icon: '⚔️', sfx: 'metal_clash', soundLabel: 'Honor to you, commander.' },
  { id: 'emote_shield', name: 'Shield Bash', icon: '🛡️', sfx: 'footstep_stone', soundLabel: 'Citadel defenses stand firm!' },
  { id: 'emote_crown', name: 'Crown Tip', icon: '👑', sfx: 'horn_check', soundLabel: 'A royal gambit.' },
  { id: 'emote_dragon', name: 'Dragon Roar', icon: '🐉', sfx: 'sorcery_cast', soundLabel: 'Beware the fiery tempest!' },
  { id: 'emote_goblin', name: 'Goblin Cackle', icon: '👺', sfx: 'ballista_release', soundLabel: 'A cunning ambush awaits.' },
  { id: 'emote_fanfare', name: 'Royal Fanfare', icon: '🎺', sfx: 'fanfare_victory', soundLabel: 'Glory to the Citadel!' },
];

export const POPULAR_CLAN_CLUBS: ClanClub[] = [
  {
    id: 'clan_ironhold',
    name: 'Ironhold Crusaders',
    tag: 'IRON',
    bannerEmblem: '🏰',
    memberCount: 84,
    totalXp: 142800,
    weeklyRank: 1,
    motto: 'No citadel falls while our blades hold true.',
  },
  {
    id: 'clan_shadow',
    name: 'Order of the Dark Bishop',
    tag: 'SHDW',
    bannerEmblem: '🗡️',
    memberCount: 62,
    totalXp: 118400,
    weeklyRank: 2,
    motto: 'Strike from the diagonals where torches cannot reach.',
  },
  {
    id: 'clan_archmage',
    name: 'Sanctum Arcanists',
    tag: 'MAGE',
    bannerEmblem: '🔮',
    memberCount: 51,
    totalXp: 98200,
    weeklyRank: 3,
    motto: 'Master the theory, conquer the monarch.',
  },
];

export interface StreamEmbed {
  id: string;
  streamerName: string;
  titleBadge?: 'GM' | 'IM' | 'FM';
  platform: 'Twitch' | 'YouTube';
  channelUrl: string;
  viewerCount: number;
  streamTitle: string;
}

export const TITLED_STREAMERS: StreamEmbed[] = [
  {
    id: 'stream_1',
    streamerName: 'GM Hikaru',
    titleBadge: 'GM',
    platform: 'Twitch',
    channelUrl: 'https://twitch.tv/gmhikaru',
    viewerCount: 14200,
    streamTitle: 'Speedrun to 3000 Elo with Crazyhouse and 960!',
  },
  {
    id: 'stream_2',
    streamerName: 'Magnus Carlsen',
    titleBadge: 'GM',
    platform: 'YouTube',
    channelUrl: 'https://youtube.com',
    viewerCount: 22800,
    streamTitle: 'World Championship Blitz Arena Live',
  },
  {
    id: 'stream_3',
    streamerName: 'Anna Cramling',
    titleBadge: 'FM',
    platform: 'Twitch',
    channelUrl: 'https://twitch.tv/annacramling',
    viewerCount: 3900,
    streamTitle: 'Citadel Tactics and Masterclass puzzles with chat',
  },
];

export interface WeeklyLeagueUser {
  rank: number;
  name: string;
  title?: string;
  rating: number;
  weeklyXp: number;
  isCurrentUser?: boolean;
}

export const WEEKLY_LEAGUE_TABLE: WeeklyLeagueUser[] = [
  { rank: 1, name: 'Valkyrie Astrid', title: 'FM', rating: 2140, weeklyXp: 2840 },
  { rank: 2, name: 'Shadowblade Morvath', title: 'CM', rating: 2025, weeklyXp: 2410 },
  { rank: 3, name: 'Crusader Baldwin', rating: 1890, weeklyXp: 2180 },
  { rank: 4, name: 'Commander Valen (You)', rating: 1200, weeklyXp: 1650, isCurrentUser: true },
  { rank: 5, name: 'Squire Gwydion', rating: 950, weeklyXp: 1420 },
  { rank: 6, name: 'Sir Tristan of Kent', rating: 1450, weeklyXp: 1190 },
];
