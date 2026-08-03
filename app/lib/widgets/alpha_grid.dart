import 'package:flutter/material.dart';

/// Grille ou liste avec en-tête défilant, filtre instantané et index
/// alphabétique de défilement rapide. Les items sont triés par nom;
/// l'index A-Z saute à la première entrée de la lettre (les hauteurs de
/// cellules étant uniformes, l'offset se calcule; la hauteur de l'en-tête
/// est mesurée à l'écran et mise en cache).
class AlphaGrid<T> extends StatefulWidget {
  const AlphaGrid({
    super.key,
    required this.items,
    required this.nameOf,
    required this.itemBuilder,
    required this.hintText,
    this.maxCrossAxisExtent = 170,
    this.childAspectRatio = 0.78,
    this.spacing = 16.0,
    this.onRefresh,
    this.trailing,
    this.header,
    this.rowExtent,
  });

  final List<T> items;
  final String Function(T) nameOf;
  final Widget Function(BuildContext, T) itemBuilder;
  final String hintText;
  final double maxCrossAxisExtent;
  final double childAspectRatio;
  final double spacing;
  final Future<void> Function()? onRefresh;

  /// Widget affiché à droite du champ de filtre (ex. bouton aléatoire).
  final Widget? trailing;

  /// En-tête qui défile avec le contenu, au-dessus du champ de filtre.
  final Widget? header;

  /// Mode liste : hauteur fixe des rangées. Absent → grille.
  final double? rowExtent;

  @override
  State<AlphaGrid<T>> createState() => _AlphaGridState<T>();
}

class _AlphaGridState<T> extends State<AlphaGrid<T>> {
  static const _gridPadding = EdgeInsets.fromLTRB(20, 12, 32, 18);
  static const _listPadding = EdgeInsets.fromLTRB(12, 8, 26, 18);

  final _scroll = ScrollController();
  final _topKey = GlobalKey();
  double _topHeight = 0;
  String _query = '';
  String? _flashLetter;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _letterOf(T item) {
    final name = widget.nameOf(item).trimLeft();
    if (name.isEmpty) return '#';
    final c = name[0].toUpperCase();
    // Replie les accents usuels sur la lettre de base.
    const folds = {
      'À': 'A', 'Â': 'A', 'Ä': 'A', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
      'Î': 'I', 'Ï': 'I', 'Ô': 'O', 'Ö': 'O', 'Û': 'U', 'Ü': 'U', 'Ù': 'U',
      'Ç': 'C',
    };
    final base = folds[c] ?? c;
    return RegExp(r'[A-Z]').hasMatch(base) ? base : '#';
  }

  void _jumpTo(String letter, List<T> sorted, double width) {
    final index = sorted.indexWhere((e) => _letterOf(e) == letter);
    if (index < 0) return;
    // En-tête + champ de filtre : hauteur mesurée quand ils sont visibles
    // (au sommet), sinon dernière valeur connue.
    final topSize = _topKey.currentContext?.size;
    if (topSize != null) _topHeight = topSize.height;

    double offset;
    final rowExtent = widget.rowExtent;
    if (rowExtent != null) {
      offset = _topHeight + _listPadding.top + index * rowExtent;
    } else {
      final usable = width - _gridPadding.horizontal;
      final columns = (usable / (widget.maxCrossAxisExtent + widget.spacing))
          .ceil()
          .clamp(1, 12);
      final cellWidth = (usable - (columns - 1) * widget.spacing) / columns;
      final cellHeight = cellWidth / widget.childAspectRatio;
      final row = index ~/ columns;
      offset =
          _topHeight + _gridPadding.top + row * (cellHeight + widget.spacing);
    }
    _scroll.jumpTo(
      offset.clamp(0, _scroll.position.maxScrollExtent).toDouble(),
    );
    setState(() => _flashLetter = letter);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.toLowerCase();
    final sorted = widget.items
        .where((e) => q.isEmpty || widget.nameOf(e).toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => widget
          .nameOf(a)
          .toLowerCase()
          .compareTo(widget.nameOf(b).toLowerCase()));
    final letters = {for (final e in sorted) _letterOf(e)};

    final scrollView = CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      // Défiler referme le clavier du filtre (sinon il reste ouvert par-dessus
      // la grille et sa bande reste réservée en bas).
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            key: _topKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.header != null) widget.header!,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          prefixIcon: const Icon(Icons.filter_list),
                          isDense: true,
                        ),
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 8),
                      widget.trailing!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (sorted.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Aucun résultat')),
          )
        else if (widget.rowExtent != null)
          SliverPadding(
            padding: _listPadding,
            sliver: SliverFixedExtentList(
              itemExtent: widget.rowExtent!,
              delegate: SliverChildBuilderDelegate(
                (context, i) => widget.itemBuilder(context, sorted[i]),
                childCount: sorted.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: _gridPadding,
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: widget.maxCrossAxisExtent,
                mainAxisSpacing: widget.spacing,
                crossAxisSpacing: widget.spacing,
                childAspectRatio: widget.childAspectRatio,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => widget.itemBuilder(context, sorted[i]),
                childCount: sorted.length,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          widget.onRefresh != null
              ? RefreshIndicator(
                  onRefresh: widget.onRefresh!, child: scrollView)
              : scrollView,
          if (_query.isEmpty && sorted.length > 30)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _AlphaBar(
                available: letters,
                onLetter: (l) => _jumpTo(l, sorted, constraints.maxWidth),
                onDone: () => setState(() => _flashLetter = null),
              ),
            ),
          if (_flashLetter != null)
            Center(
              child: Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _flashLetter!,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AlphaBar extends StatelessWidget {
  const _AlphaBar({
    required this.available,
    required this.onLetter,
    required this.onDone,
  });

  static const _letters = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  final Set<String> available;
  final void Function(String) onLetter;
  final VoidCallback onDone;

  void _handle(BuildContext context, Offset localPosition, double height) {
    final i =
        (localPosition.dy / height * _letters.length).floor().clamp(0, 26);
    final letter = _letters[i];
    if (available.contains(letter)) onLetter(letter);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) =>
            _handle(context, d.localPosition, c.maxHeight),
        onVerticalDragEnd: (_) => onDone(),
        onTapDown: (d) => _handle(context, d.localPosition, c.maxHeight),
        onTapUp: (_) => onDone(),
        child: SizedBox(
          width: 24,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final l in _AlphaBar._letters)
                Text(
                  l,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: available.contains(l)
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
