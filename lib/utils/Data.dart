import 'package:html/dom.dart';

extension Parsing on Element {
  List<List<String>> get toMatrix => querySelectorAll('tr')
      .map(
        (Element row) => row
            .querySelectorAll('th, td')
            .map((Element cell) => cell.text)
            .toList(),
      )
      .toList();
}
