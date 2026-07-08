import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:myapp/ui/widgets/app_feedback.dart';
import 'package:printing/printing.dart';
import '../core/utils/pdf_generator.dart';
import '../logic/match_game_controller.dart';

class PdfPreviewScreen extends StatefulWidget {
  final MatchState state;
  final String teamAName;
  final String teamBName;
  final String tournamentName;
  final String categoryName;
  final String tournamentLogoUrl;
  final String refereeLogoUrl;
  final String venueName;
  final String mainReferee;
  final String auxReferee;
  final String scorekeeper;
  final Uint8List? protestSignature;
  final String coachA;
  final String coachB;
  final int? captainAId;
  final int? captainBId;
  final DateTime? matchDate;
  final Uint8List? mainRefSignature;
  final Uint8List? auxRefSignature;

  const PdfPreviewScreen({
    super.key,
    required this.state,
    required this.teamAName,
    required this.teamBName,
    required this.tournamentName,
    required this.categoryName,
    required this.tournamentLogoUrl,
    required this.refereeLogoUrl,
    required this.venueName,
    required this.mainReferee,
    required this.auxReferee,
    required this.scorekeeper,
    this.protestSignature,
    this.coachA = "",
    this.coachB = "",
    this.captainAId,
    this.captainBId,
    this.matchDate,
    this.mainRefSignature,
    this.auxRefSignature,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  // Guardamos el Future UNA sola vez. Así la rotación NO regenera el PDF.
  Future<Uint8List>? _pdfFuture;

  @override
  void initState() {
    super.initState();
    _pdfFuture = _generate();
  }

  Future<Uint8List> _generate() {
    return PdfGenerator.generateBytes(
      widget.state,
      widget.teamAName,
      widget.teamBName,
      tournamentName: widget.tournamentName,
      categoryName: widget.categoryName,
      tournamentLogoUrl: widget.tournamentLogoUrl,
      refereeLogoUrl: widget.refereeLogoUrl,
      venueName: widget.venueName,
      mainReferee: widget.mainReferee,
      auxReferee: widget.auxReferee,
      scorekeeper: widget.scorekeeper,
      protestSignature: widget.protestSignature,
      coachA: widget.coachA,
      coachB: widget.coachB,
      captainAId: widget.captainAId,
      captainBId: widget.captainBId,
      matchDate: widget.matchDate,
      mainRefSignature: widget.mainRefSignature,
      auxRefSignature: widget.auxRefSignature,
    );
  }

  void _sharePdf() async {
    try {
      await PdfGenerator.generateAndShare(
        widget.state,
        widget.teamAName,
        widget.teamBName,
        tournamentName: widget.tournamentName,
        categoryName: widget.categoryName,
        tournamentLogoUrl: widget.tournamentLogoUrl,
        refereeLogoUrl: widget.refereeLogoUrl,
        venueName: widget.venueName,
        mainReferee: widget.mainReferee,
        auxReferee: widget.auxReferee,
        scorekeeper: widget.scorekeeper,
        protestSignature: widget.protestSignature,
        coachA: widget.coachA,
        coachB: widget.coachB,
        captainAId: widget.captainAId,
        captainBId: widget.captainBId,
        matchDate: widget.matchDate,
        mainRefSignature: widget.mainRefSignature,
        auxRefSignature: widget.auxRefSignature,
      );
    } catch (e) {
      if (mounted) context.showError("Error al compartir: $e");
    }
  }

  void _downloadPdf() async {
    try {
      await PdfGenerator.generateAndPreview(
        widget.state,
        widget.teamAName,
        widget.teamBName,
        tournamentName: widget.tournamentName,
        categoryName: widget.categoryName,
        tournamentLogoUrl: widget.tournamentLogoUrl,
        refereeLogoUrl: widget.refereeLogoUrl,
        venueName: widget.venueName,
        mainReferee: widget.mainReferee,
        auxReferee: widget.auxReferee,
        scorekeeper: widget.scorekeeper,
        protestSignature: widget.protestSignature,
        coachA: widget.coachA,
        coachB: widget.coachB,
        captainAId: widget.captainAId,
        captainBId: widget.captainBId,
        matchDate: widget.matchDate,
        mainRefSignature: widget.mainRefSignature,
        auxRefSignature: widget.auxRefSignature,
      );
    } catch (e) {
      if (mounted) context.showError("Error al descargar: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vista Previa del Acta", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1F2B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download, size: 28),
            tooltip: "Compartir PDF",
            onPressed: _downloadPdf,
          ),
          IconButton(
            icon: const Icon(Icons.share, size: 28),
            tooltip: "Descargar PDF",
            onPressed: _sharePdf,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _pdfFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text("No se pudo generar el acta:\n${snapshot.error}",
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
              ),
            );
          }
          final bytes = snapshot.data!;
          return PdfPreview(
            // Ya tenemos los bytes generados; PdfPreview solo los muestra.
            build: (format) => bytes,
            useActions: false,
            canChangePageFormat: false,
            canDebug: false,
          );
        },
      ),
    );
  }
}