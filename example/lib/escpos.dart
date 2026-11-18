/// Renders a JSON print job as a plain ESC/POS text receipt.
///
/// `{'text': '...'}` prints the text as-is; any other map prints `key: value` lines.
List<int> escPosReceipt(dynamic job) {
  final text = job is Map && job['text'] != null
      ? job['text'].toString()
      : job is Map
          ? job.entries.map((e) => '${e.key}: ${e.value}').join('\n')
          : '$job';
  return [
    0x1B, 0x40, // ESC @ : reset printer
    // shortcut: ASCII only (others print as '?'), add a code page for local scripts.
    ...text.codeUnits.map((c) => c < 128 ? c : 0x3F),
    0x0A, 0x0A, 0x0A, 0x0A, // feed past the tear bar
  ];
}
