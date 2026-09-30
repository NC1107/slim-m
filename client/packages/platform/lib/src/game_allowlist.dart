// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The games rich presence may ever name (decision 0044).
///
/// Detection matches running programs against this list and nothing else, so
/// a program that is not here is never reported, stored or logged. It ships
/// with the client and Settings shows it in full. It is deliberately short:
/// adding a game is a code change someone reviews, not a runtime setting.
library;

/// One game, recognised by its process names and, for Steam titles, its app
/// id. Process names are lowercase without `.exe`, so one entry covers the
/// Windows, Linux and macOS spelling.
class AllowedGame {
  const AllowedGame(this.name, {this.processes = const [], this.steamAppId});

  final String name;
  final List<String> processes;
  final int? steamAppId;
}

const gameAllowlist = <AllowedGame>[
  AllowedGame('Apex Legends', processes: ['r5apex'], steamAppId: 1172470),
  AllowedGame(
    'Baldur\'s Gate 3',
    processes: ['bg3', 'bg3_dx11'],
    steamAppId: 1086940,
  ),
  AllowedGame(
    'Counter-Strike 2',
    processes: ['cs2'],
    steamAppId: 730,
  ),
  AllowedGame(
    'Cyberpunk 2077',
    processes: ['cyberpunk2077'],
    steamAppId: 1091500,
  ),
  AllowedGame('Deep Rock Galactic',
      processes: ['fsd-win64-shipping'], steamAppId: 548430),
  AllowedGame('Dota 2', processes: ['dota2'], steamAppId: 570),
  AllowedGame('Elden Ring', processes: ['eldenring'], steamAppId: 1245620),
  AllowedGame('Factorio', processes: ['factorio'], steamAppId: 427520),
  AllowedGame('Fortnite', processes: ['fortniteclient-win64-shipping']),
  AllowedGame('Grand Theft Auto V', processes: ['gta5'], steamAppId: 271590),
  AllowedGame('Helldivers 2', processes: ['helldivers2'], steamAppId: 553850),
  AllowedGame('League of Legends', processes: ['league of legends']),
  AllowedGame(
    'Lethal Company',
    processes: ['lethal company'],
    steamAppId: 1966720,
  ),
  AllowedGame('Minecraft (Bedrock)', processes: ['minecraft.windows']),
  AllowedGame(
    'Palworld',
    processes: ['palworld-win64-shipping'],
    steamAppId: 1623730,
  ),
  AllowedGame('Path of Exile', processes: ['pathofexile']),
  AllowedGame('Rocket League', processes: ['rocketleague'], steamAppId: 252950),
  AllowedGame('Rust', processes: ['rustclient'], steamAppId: 252490),
  AllowedGame(
    'Satisfactory',
    processes: ['factorygame-win64-shipping'],
    steamAppId: 526870,
  ),
  AllowedGame('Stardew Valley',
      processes: ['stardew valley'], steamAppId: 413150),
  AllowedGame('Team Fortress 2', steamAppId: 440),
  AllowedGame('Terraria', processes: ['terraria'], steamAppId: 105600),
  AllowedGame('Valorant', processes: ['valorant-win64-shipping']),
];
