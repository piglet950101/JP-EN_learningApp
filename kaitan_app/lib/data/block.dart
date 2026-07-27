// The 46-block definition (client-confirmed 2026-05-22, Q-2).
// Derived from the formula: vol.1 = ceil(id/48), vol.2 = 23 + ceil((id-1100)/48).
// vol.1 last block (23) = 44 words; vol.2 last block (46) = 45; rest = 48.

class Block {
  final int no;        // 1..46
  final int vol;       // 1 or 2
  final int firstId;
  final int lastId;
  const Block({
    required this.no,
    required this.vol,
    required this.firstId,
    required this.lastId,
  });
  int get count => lastId - firstId + 1;
  String get label => '$no\n$firstId–$lastId';
}

const List<Block> kAllBlocks = [
  Block(no: 1, vol: 1, firstId: 1, lastId: 48),
  Block(no: 2, vol: 1, firstId: 49, lastId: 96),
  Block(no: 3, vol: 1, firstId: 97, lastId: 144),
  Block(no: 4, vol: 1, firstId: 145, lastId: 192),
  Block(no: 5, vol: 1, firstId: 193, lastId: 240),
  Block(no: 6, vol: 1, firstId: 241, lastId: 288),
  Block(no: 7, vol: 1, firstId: 289, lastId: 336),
  Block(no: 8, vol: 1, firstId: 337, lastId: 384),
  Block(no: 9, vol: 1, firstId: 385, lastId: 432),
  Block(no: 10, vol: 1, firstId: 433, lastId: 480),
  Block(no: 11, vol: 1, firstId: 481, lastId: 528),
  Block(no: 12, vol: 1, firstId: 529, lastId: 576),
  Block(no: 13, vol: 1, firstId: 577, lastId: 624),
  Block(no: 14, vol: 1, firstId: 625, lastId: 672),
  Block(no: 15, vol: 1, firstId: 673, lastId: 720),
  Block(no: 16, vol: 1, firstId: 721, lastId: 768),
  Block(no: 17, vol: 1, firstId: 769, lastId: 816),
  Block(no: 18, vol: 1, firstId: 817, lastId: 864),
  Block(no: 19, vol: 1, firstId: 865, lastId: 912),
  Block(no: 20, vol: 1, firstId: 913, lastId: 960),
  Block(no: 21, vol: 1, firstId: 961, lastId: 1008),
  Block(no: 22, vol: 1, firstId: 1009, lastId: 1056),
  Block(no: 23, vol: 1, firstId: 1057, lastId: 1100), // 44 words
  Block(no: 24, vol: 2, firstId: 1101, lastId: 1148),
  Block(no: 25, vol: 2, firstId: 1149, lastId: 1196),
  Block(no: 26, vol: 2, firstId: 1197, lastId: 1244),
  Block(no: 27, vol: 2, firstId: 1245, lastId: 1292),
  Block(no: 28, vol: 2, firstId: 1293, lastId: 1340),
  Block(no: 29, vol: 2, firstId: 1341, lastId: 1388),
  Block(no: 30, vol: 2, firstId: 1389, lastId: 1436),
  Block(no: 31, vol: 2, firstId: 1437, lastId: 1484),
  Block(no: 32, vol: 2, firstId: 1485, lastId: 1532),
  Block(no: 33, vol: 2, firstId: 1533, lastId: 1580),
  Block(no: 34, vol: 2, firstId: 1581, lastId: 1628),
  Block(no: 35, vol: 2, firstId: 1629, lastId: 1676),
  Block(no: 36, vol: 2, firstId: 1677, lastId: 1724),
  Block(no: 37, vol: 2, firstId: 1725, lastId: 1772),
  Block(no: 38, vol: 2, firstId: 1773, lastId: 1820),
  Block(no: 39, vol: 2, firstId: 1821, lastId: 1868),
  Block(no: 40, vol: 2, firstId: 1869, lastId: 1916),
  Block(no: 41, vol: 2, firstId: 1917, lastId: 1964),
  Block(no: 42, vol: 2, firstId: 1965, lastId: 2012),
  Block(no: 43, vol: 2, firstId: 2013, lastId: 2060),
  Block(no: 44, vol: 2, firstId: 2061, lastId: 2108),
  Block(no: 45, vol: 2, firstId: 2109, lastId: 2156),
  Block(no: 46, vol: 2, firstId: 2157, lastId: 2201), // 45 words
];

List<Block> blocksOfVol(int vol) =>
    kAllBlocks.where((b) => b.vol == vol).toList();
