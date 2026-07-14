/// What a bulk buy is measured in — and, because of that, whether it can be
/// divided at all.
///
/// The unit carries the rule rather than a separate flag someone has to
/// remember to set: a poster choosing "pieces" has already said the goods
/// cannot be halved.
///
/// Grams and millilitres are deliberately absent. They would give two ways to
/// spell the same buy (500 g vs 0.5 kg), and the amount is a decimal, so the
/// large unit covers every case with one canonical spelling.
enum DealUnit {
  kg('kg', 'kg', continuous: true),
  litre('L', 'L', continuous: true),
  pieces('pieces', 'piece', continuous: false),
  packs('packs', 'pack', continuous: false),
  bottles('bottles', 'bottle', continuous: false),
  cans('cans', 'can', continuous: false),
  sachets('sachets', 'sachet', continuous: false);

  const DealUnit(this.label, this.singularLabel, {required this.continuous});

  /// Shown next to an amount: "25 kg", "24 bottles".
  final String label;

  /// Shown when there is exactly one: "1 bottle". Weights and volumes never
  /// pluralise, so their two labels are the same.
  final String singularLabel;

  /// Weights and volumes divide freely. Countable things do not.
  final bool continuous;

  bool get discrete => !continuous;
}
