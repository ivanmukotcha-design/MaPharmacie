import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final publicInformationProvider = FutureProvider<PublicInformation>((
  ref,
) async {
  final source = await rootBundle.loadString('admin/public/legal.json');
  return PublicInformation.fromJson(jsonDecode(source) as Map<String, dynamic>);
});

final publicLinkLauncherProvider = Provider<Future<bool> Function(Uri)>((ref) {
  return (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
});

class PublicInformation {
  final String appName;
  final String publisherName;
  final String supportEmail;
  final String effectiveDate;
  final bool approvedForPublication;
  final Uri website;
  final List<Map<String, String>> sections;
  final String deletionWarning;
  final List<String> deletionSteps;
  final String deletionSubject;
  final String deletionBody;

  PublicInformation.fromJson(Map<String, dynamic> data)
    : appName = data['appName'] as String,
      publisherName = data['publisherName'] as String,
      supportEmail = data['supportEmail'] as String,
      effectiveDate = data['effectiveDate'] as String,
      approvedForPublication = data['approvedForPublication'] == true,
      website = Uri.parse(data['website'] as String),
      sections = (data['sections'] as List)
          .map((section) => Map<String, String>.from(section as Map))
          .toList(),
      deletionWarning = data['deletion']['warning'] as String,
      deletionSteps = List<String>.from(data['deletion']['steps'] as List),
      deletionSubject = data['deletion']['subject'] as String,
      deletionBody = data['deletion']['body'] as String;

  bool get ready =>
      approvedForPublication &&
      appName.trim().isNotEmpty &&
      publisherName.trim().isNotEmpty &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(supportEmail) &&
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(effectiveDate) &&
      DateTime.tryParse(effectiveDate) != null &&
      DateTime.parse(
        effectiveDate,
      ).toIso8601String().startsWith(effectiveDate) &&
      website.scheme == 'https' &&
      website.host.isNotEmpty &&
      sections.isNotEmpty &&
      sections.every(
        (section) =>
            (section['title'] ?? '').trim().isNotEmpty &&
            (section['body'] ?? '').trim().isNotEmpty,
      ) &&
      deletionWarning.trim().isNotEmpty &&
      deletionSteps.isNotEmpty &&
      deletionSteps.every((step) => step.trim().isNotEmpty) &&
      deletionSubject.trim().isNotEmpty &&
      deletionBody.trim().isNotEmpty;

  Uri get privacyUrl => website.resolve('/confidentialite.html');
  Uri get deletionUrl => website.resolve('/suppression-compte.html');

  Uri get deletionEmail {
    if (!ready) throw StateError('Informations publiques non validées');
    return Uri(
      scheme: 'mailto',
      path: supportEmail,
      query:
          'subject=${Uri.encodeComponent(deletionSubject)}&body=${Uri.encodeComponent(deletionBody)}',
    );
  }
}
