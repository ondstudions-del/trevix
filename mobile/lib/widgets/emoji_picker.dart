import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// Emojis por categoría (los del teclado de iOS más usados). Se dibujan con la fuente del sistema.
const emojiCategories = <(String, IconData, String)>[
  ('Caras', CupertinoIcons.smiley,
      '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 🫠 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🫢 🫣 🤫 🤔 🫡 🤐 🤨 😐 😑 😶 🫥 😏 😒 🙄 😬 😮‍💨 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 😵‍💫 🤯 🤠 🥳 🥸 😎 🤓 🧐 😕 🫤 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 🥹 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖 😺 😸 😹 😻 😼 😽 🙀 😿 😾'),
  ('Gestos', CupertinoIcons.hand_raised,
      '👋 🤚 🖐️ ✋ 🖖 🫱 🫲 🫳 🫴 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 🫵 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🦵 🦶 👂 👃 🧠 👀 👁️ 👅 👄 🫦 🙋 🙆 🙅 🤷 🤦 💁 🙇 🧏 💃 🕺 👯 🏃 🚶 🧍'),
  ('Corazones', CupertinoIcons.heart,
      '❤️ 🩷 🧡 💛 💚 💙 🩵 💜 🖤 🩶 🤍 🤎 💔 ❤️‍🔥 ❤️‍🩹 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 💌 💋 💯 💢 💥 💫 💦 💨 🕳️ 💬 💭 💤 ✨ 🔥 ⭐ 🌟 ⚡ 🌈 ☀️ 🌙'),
  ('Animales', CupertinoIcons.paw,
      '🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🦋 🐌 🐞 🐢 🐍 🦖 🐙 🦑 🦀 🐠 🐬 🐳 🦈 🐊 🐘 🦒 🦓 🐪 🐎 🐕 🐈 🐓 🦚 🦜 🌵 🌲 🌴 🌱 🌿 🍀 🍁 🍂 🌷 🌹 🌺 🌸 🌼 🌻 💐'),
  ('Comida', CupertinoIcons.cart,
      '🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🥑 🍆 🥔 🥕 🌽 🌶️ 🥒 🥦 🍄 🥜 🍞 🥐 🥖 🧀 🥚 🍳 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🥪 🌮 🌯 🥗 🍝 🍜 🍲 🍣 🍱 🍤 🍙 🍚 🍦 🍩 🍪 🎂 🍰 🧁 🍫 🍬 🍭 🍿 ☕ 🍵 🧋 🥤 🍺 🍻 🥂 🍷 🍸 🍹 🍾'),
  ('Actividades', CupertinoIcons.sportscourt,
      '⚽ 🏀 🏈 ⚾ 🎾 🏐 🏉 🎱 🏓 🏸 🥊 🥋 ⛳ 🛹 🛼 ⛸️ 🎿 🏂 🏋️ 🤸 ⛹️ 🤾 🏌️ 🏄 🏊 🚴 🏆 🥇 🥈 🥉 🏅 🎖️ 🎗️ 🎫 🎟️ 🎪 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🎻 🎲 🎯 🎳 🎮 🎰 🧩 🎉 🎊 🎈 🎁 🪅'),
  ('Viajes', CupertinoIcons.airplane,
      '🚗 🚕 🚙 🚌 🏎️ 🚓 🚑 🚒 🚚 🚜 🏍️ 🛵 🚲 🛴 🚨 🚆 🚇 ✈️ 🛫 🛬 🚀 🛸 🚁 ⛵ 🚤 🛳️ ⚓ 🗺️ 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🏕️ 🏠 🏡 🏢 🏥 🏦 🏨 ⛪ 🕌 🌅 🌄 🌇 🌆 🌃 🌉 🌌 🎆 🎇'),
  ('Objetos', CupertinoIcons.lightbulb,
      '⌚ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 💾 💿 📷 📸 📹 🎥 📞 ☎️ 📺 📻 🎙️ ⏰ ⌛ 💡 🔦 🕯️ 💸 💵 💰 💳 💎 🔧 🔨 🛠️ 🔑 🗝️ 🔒 🔓 🧸 🪄 🎀 🛍️ 🎓 👑 💍 👓 🕶️ 👗 👠 👟 🧢 🎒 📚 📖 ✏️ 🖊️ 📝 📌 📎 ✂️ 📅 📈 📉 🧪 💊 🩹'),
  ('Símbolos', CupertinoIcons.number,
      '✅ ☑️ ✔️ ❌ ❎ ➕ ➖ ➗ ✖️ ❓ ❔ ❗ ❕ ‼️ ⁉️ 💲 ♻️ ⚠️ 🚫 ⛔ 🔞 📵 🆗 🆒 🆕 🆓 🆙 🆘 🔝 🔜 ⏩ ⏪ ▶️ ⏸️ ⏹️ 🔀 🔁 🔂 🎵 🎶 ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ 🔄 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟤 🔺 🔻 🔷 🔶 ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓'),
  ('Banderas', CupertinoIcons.flag,
      '🏳️ 🏴 🏁 🚩 🏳️‍🌈 🇨🇴 🇲🇽 🇦🇷 🇨🇱 🇵🇪 🇪🇨 🇻🇪 🇧🇴 🇺🇾 🇵🇾 🇨🇷 🇵🇦 🇬🇹 🇭🇳 🇸🇻 🇳🇮 🇨🇺 🇩🇴 🇵🇷 🇪🇸 🇺🇸 🇨🇦 🇧🇷 🇬🇧 🇫🇷 🇮🇹 🇩🇪 🇵🇹 🇯🇵 🇰🇷 🇨🇳 🇮🇳'),
];

/// Emojis rápidos para comentar y reaccionar.
const quickEmojis = ['❤️', '😂', '😍', '🔥', '👏', '😮', '😢', '🙌'];

/// Recientes del teléfono (los últimos 24 elegidos).
class RecentEmojis {
  static const _key = 'recent_emojis';
  static List<String> _cache = const [];

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    _cache = prefs.getStringList(_key) ?? const [];
    return _cache;
  }

  static List<String> get cached => _cache;

  static Future<void> add(String emoji) async {
    final next = [emoji, ..._cache.where((e) => e != emoji)].take(24).toList();
    _cache = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next);
  }
}

/// Cuadrícula de emojis con pestañas por categoría y «Recientes». [dark] para pantallas sobre fotos o video.
class EmojiGrid extends StatefulWidget {
  const EmojiGrid({super.key, required this.onPick, this.dark = false, this.height = 300});

  final ValueChanged<String> onPick;
  final bool dark;
  final double height;

  @override
  State<EmojiGrid> createState() => _EmojiGridState();
}

class _EmojiGridState extends State<EmojiGrid> {
  int _tab = 0;
  List<String> _recent = RecentEmojis.cached;

  @override
  void initState() {
    super.initState();
    RecentEmojis.load().then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  void _pick(String e) {
    RecentEmojis.add(e);
    widget.onPick(e);
  }

  @override
  Widget build(BuildContext context) {
    final hasRecent = _recent.isNotEmpty;
    final tabs = <(String, IconData, List<String>)>[
      if (hasRecent) (tr('Recientes'), CupertinoIcons.clock, _recent),
      for (final c in emojiCategories) (tr(c.$1), c.$2, c.$3.split(' ').where((e) => e.isNotEmpty).toList()),
    ];
    final index = _tab.clamp(0, tabs.length - 1);
    final fg = widget.dark ? Colors.white : Tx.text;
    final muted = widget.dark ? Colors.white54 : Tx.subtle;
    return SizedBox(
      height: widget.height,
      child: Column(children: [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (var i = 0; i < tabs.length; i++)
              GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: Container(
                  width: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? (widget.dark ? Colors.white24 : Tx.alpha(Tx.accent, .15)) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(tabs[i].$2, size: 20, color: i == index ? fg : muted),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
          child: Align(alignment: Alignment.centerLeft, child: Text(tabs[index].$1, style: Tx.body(12, weight: FontWeight.w700, color: muted))),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 46, mainAxisSpacing: 2, crossAxisSpacing: 2),
            itemCount: tabs[index].$3.length,
            itemBuilder: (_, i) {
              final e = tabs[index].$3[i];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _pick(e),
                child: Center(child: Text(e, style: const TextStyle(fontSize: 28))),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Hoja con la cuadrícula de emojis. Devuelve el emoji elegido.
Future<String?> pickEmoji(BuildContext context, {bool dark = false}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom),
      decoration: BoxDecoration(
        color: dark ? const Color(0xF2141418) : Tx.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 38, height: 4, decoration: BoxDecoration(color: dark ? Colors.white30 : Tx.border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 6),
        EmojiGrid(dark: dark, height: 340, onPick: (e) => Navigator.pop(ctx, e)),
      ]),
    ),
  );
}
