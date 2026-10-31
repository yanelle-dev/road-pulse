import 'package:flutter/material.dart';

import '../address_service.dart';

/// Подпись места дефекта: название дороги с сервера сразу, запасной адрес — после геокодера.
class DefectAddress extends StatefulWidget {
  final Map<String, dynamic> defect;
  final TextStyle style;

  const DefectAddress({super.key, required this.defect, required this.style});

  @override
  State<DefectAddress> createState() => _DefectAddressState();
}

class _DefectAddressState extends State<DefectAddress> {
  String? _text;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant DefectAddress old) {
    super.didUpdateWidget(old);
    if (old.defect['cluster_id'] != widget.defect['cluster_id']) _resolve();
  }

  Future<void> _resolve() async {
    final instant = AddressService.fromDefect(widget.defect);
    setState(() {
      _text = instant;
      _resolved = instant != null;
    });
    if (instant != null) return;

    final address = await AddressService.resolve(widget.defect);
    if (!mounted) return;
    setState(() {
      _text = address;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _text ?? (_resolved ? 'Дорога без названия' : 'Определение адреса...');
    return Text(label, style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}