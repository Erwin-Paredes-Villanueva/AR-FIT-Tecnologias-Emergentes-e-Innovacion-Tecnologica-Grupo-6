import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../product/product_detail.dart';

class _Msg {
  final String role; // user | model
  final String text;
  final List<String> productIds;
  _Msg(this.role, this.text, [this.productIds = const []]);
}

/// Asistente virtual de compra (Google Gemini) con el catálogo y el perfil del
/// usuario como contexto.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _thinking = false;

  static const _suggestions = [
    'Arma un outfit casual para el fin de semana',
    '¿Qué me pongo para una entrevista de trabajo?',
    '¿Qué talla de jean me recomiendas?',
    'Algo elegante por menos de S/ 200',
  ];

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _thinking) return;
    _input.clear();
    setState(() {
      _messages.add(_Msg('user', text.trim()));
      _thinking = true;
    });
    _scrollDown();
    try {
      final res = await Api.fn('assistant', {
        'messages': [for (final m in _messages) {'role': m.role, 'text': m.text}],
      });
      setState(() => _messages.add(_Msg('model', res['reply'] as String, List<String>.from(res['product_ids'] ?? []))));
    } catch (e) {
      setState(() => _messages.add(_Msg('model', 'Lo siento, no pude responder ahora ($e).')));
    } finally {
      if (mounted) setState(() => _thinking = false);
      _scrollDown();
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          CircleAvatar(radius: 16, backgroundColor: AppColors.ai, child: Icon(Icons.auto_awesome, size: 17, color: Colors.white)),
          SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ari', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text('Asistente de compra · Gemini', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ]),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(tooltip: 'Nueva conversación', onPressed: () => setState(_messages.clear), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? ListView(padding: const EdgeInsets.all(20), children: [
                  const SizedBox(height: 20),
                  const Icon(Icons.auto_awesome, size: 48, color: AppColors.ai),
                  const SizedBox(height: 12),
                  Text('¡Hola ${state.profile!.fullName.split(' ').first}! Soy Ari',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text(
                    'Conozco tus medidas, tu estilo y todo el catálogo. Pregúntame lo que quieras.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 22),
                  for (final s in _suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                        onPressed: () => _send(s),
                        child: Text(s, style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                    ),
                ])
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _messages.length + (_thinking ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _messages.length) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ai)),
                        ),
                      );
                    }
                    return _Bubble(msg: _messages[i], products: [
                      for (final id in _messages[i].productIds)
                        if (state.productById(id) != null) state.productById(id)!,
                    ]);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Escribe tu consulta…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: AppColors.ai),
                onPressed: _thinking ? null : () => _send(_input.text),
                icon: const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.products});
  final _Msg msg;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final mine = msg.role == 'user';
    return Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: mine ? AppColors.ink : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Text(msg.text, style: TextStyle(color: mine ? Colors.white : AppColors.ink, height: 1.35)),
      ),
      if (products.isNotEmpty)
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final p = products[i];
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(product: p))),
                child: SizedBox(
                  width: 120,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: GarmentImage(p.imageUrl, padding: 8, radius: 12)),
                    const SizedBox(height: 4),
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(money.format(p.price), style: const TextStyle(fontSize: 12, color: AppColors.accent)),
                  ]),
                ),
              );
            },
          ),
        ),
    ]);
  }
}
