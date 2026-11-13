import 'dart:io';

/// Enforces platform import/export boundaries across the glVolition codebase:
///
/// - Core engine (`lib/gl_volition.dart`, `lib/src/engine.dart`, `lib/src/engine/**`):
///   must NOT import or export `dart:io`, `dart:ffi`, `dart:isolate`,
///   `package:web`, `dart:js_interop`, or `dart:html`.
/// - Web host (`lib/gl_volition_web.dart`, `lib/src/web/**`):
///   must NOT import or export `dart:io` or `dart:ffi`.
/// - Native host (`lib/gl_volition_native.dart`, `lib/src/native/**`):
///   must NOT import or export `package:web`, `dart:js_interop`, or `dart:html`.
void main(List<String> args) {
  String? explicitRoot;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      stdout.writeln(
        'Usage: dart run tool/check_boundaries.dart [--root <repo-dir>]',
      );
      return;
    } else if (arg == '--root' && i + 1 < args.length) {
      explicitRoot = args[++i];
    } else {
      stderr.writeln('Unknown or incomplete argument: $arg');
      stderr.writeln(
        'Usage: dart run tool/check_boundaries.dart [--root <repo-dir>]',
      );
      exit(64);
    }
  }

  final root = explicitRoot != null
      ? Directory(explicitRoot).absolute
      : _resolveRepoRoot();
  if (!root.existsSync()) {
    stderr.writeln('Root directory does not exist: ${root.path}');
    exit(2);
  }
  final rules = <_BoundaryRule>[
    const _BoundaryRule(
      name: 'pure-dart-core',
      files: ['lib/gl_volition.dart', 'lib/src/engine.dart'],
      directories: ['lib/src/engine'],
      forbiddenTargets: [
        'dart:io',
        'dart:ffi',
        'dart:isolate',
        'package:web',
        'dart:js_interop',
        'dart:html',
      ],
    ),
    const _BoundaryRule(
      name: 'web-host',
      files: ['lib/gl_volition_web.dart'],
      directories: ['lib/src/web'],
      forbiddenTargets: ['dart:io', 'dart:ffi'],
    ),
    const _BoundaryRule(
      name: 'native-host',
      files: ['lib/gl_volition_native.dart'],
      directories: ['lib/src/native'],
      forbiddenTargets: ['package:web', 'dart:js_interop', 'dart:html'],
    ),
  ];

  final violations = <String>[];
  final countsByRule = <String, int>{};

  for (final rule in rules) {
    final files = _collectTargetFiles(root, rule, violations);
    countsByRule[rule.name] = files.length;

    for (final file in files) {
      final relPath = _relativeSlashPath(root.path, file.path);
      final source = file.readAsStringSync();
      final directives = _extractImportExportDirectives(source);

      for (final directive in directives) {
        final forbidden = _matchForbiddenTarget(
          directive.uri,
          rule.forbiddenTargets,
        );
        if (forbidden != null) {
          violations.add(
            '$relPath:${directive.line}: forbidden ${directive.keyword} '
            '"${directive.uri}" (violates ${rule.name} boundary: $forbidden)',
          );
        }
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln(
      'Boundary check FAILED (${violations.length} violation(s)):',
    );
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exit(1);
  }

  final totalFiles = countsByRule.values.fold<int>(0, (sum, n) => sum + n);
  final summary = countsByRule.entries
      .map((e) => '${e.key}: ${e.value}')
      .join(', ');
  stdout.writeln(
    'Boundary check passed: scanned $totalFiles file(s) ($summary) with 0 violations.',
  );
}

final class _BoundaryRule {
  final String name;
  final List<String> files;
  final List<String> directories;
  final List<String> forbiddenTargets;

  const _BoundaryRule({
    required this.name,
    required this.files,
    required this.directories,
    required this.forbiddenTargets,
  });
}

final class _DirectiveUri {
  final String keyword;
  final String uri;
  final int line;

  const _DirectiveUri({
    required this.keyword,
    required this.uri,
    required this.line,
  });
}

Directory _resolveRepoRoot() {
  final cwd = Directory.current;
  if (_looksLikeRepoRoot(cwd)) return cwd;

  var dir = File.fromUri(Platform.script).absolute.parent;
  while (true) {
    if (_looksLikeRepoRoot(dir)) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  stderr.writeln('Unable to locate repository root from ${cwd.path}.');
  exit(2);
}

bool _looksLikeRepoRoot(Directory dir) {
  final sep = Platform.pathSeparator;
  return File('${dir.path}${sep}pubspec.yaml').existsSync() &&
      File('${dir.path}${sep}lib${sep}gl_volition.dart').existsSync();
}

List<File> _collectTargetFiles(
  Directory root,
  _BoundaryRule rule,
  List<String> violations,
) {
  final seen = <String>{};
  final result = <File>[];
  final sep = Platform.pathSeparator;

  for (final relFile in rule.files) {
    final file = File('${root.path}$sep${relFile.replaceAll('/', sep)}');
    if (!file.existsSync()) {
      violations.add(
        '$relFile:1: required file missing for ${rule.name} check',
      );
      continue;
    }
    final key = _relativeSlashPath(root.path, file.path);
    if (seen.add(key)) result.add(file);
  }

  for (final relDir in rule.directories) {
    final dir = Directory('${root.path}$sep${relDir.replaceAll('/', sep)}');
    if (!dir.existsSync()) {
      violations.add(
        '$relDir:1: required directory missing for ${rule.name} check',
      );
      continue;
    }
    final dartFiles =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort(
            (a, b) => _relativeSlashPath(
              root.path,
              a.path,
            ).compareTo(_relativeSlashPath(root.path, b.path)),
          );
    for (final file in dartFiles) {
      final key = _relativeSlashPath(root.path, file.path);
      if (seen.add(key)) result.add(file);
    }
  }

  return result;
}

String _relativeSlashPath(String rootPath, String fullPath) {
  final normRoot = rootPath
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '');
  final normFull = fullPath.replaceAll('\\', '/');
  if (normFull.startsWith('$normRoot/')) {
    return normFull.substring(normRoot.length + 1);
  }
  return normFull;
}

String? _matchForbiddenTarget(String uri, List<String> forbiddenTargets) {
  for (final forbidden in forbiddenTargets) {
    if (uri == forbidden || uri.startsWith('$forbidden/')) {
      return forbidden;
    }
    if (forbidden == 'dart:js_interop' && uri == 'dart:js_interop_unsafe') {
      return forbidden;
    }
  }
  return null;
}

/// Tokenizes [source] while stripping comments (`//`, `///`, nested `/* ... */`)
/// and properly scanning string literals (including raw and triple-quoted
/// strings and `${...}` interpolations), returning all URIs from top-level
/// `import` / `export` directives along with their 1-based line numbers.
List<_DirectiveUri> _extractImportExportDirectives(String source) {
  final tokens = _DartLexer(source).tokenize();
  final directives = <_DirectiveUri>[];

  var braceDepth = 0;
  var parenDepth = 0;
  var bracketDepth = 0;

  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    switch (token.kind) {
      case _TokenKind.lbrace:
        braceDepth++;
      case _TokenKind.rbrace:
        if (braceDepth > 0) braceDepth--;
      case _TokenKind.lparen:
        parenDepth++;
      case _TokenKind.rparen:
        if (parenDepth > 0) parenDepth--;
      case _TokenKind.lbracket:
        bracketDepth++;
      case _TokenKind.rbracket:
        if (bracketDepth > 0) bracketDepth--;
      case _TokenKind.word:
        if (braceDepth != 0 || parenDepth != 0 || bracketDepth != 0) {
          continue;
        }
        if (token.value != 'import' && token.value != 'export') {
          continue;
        }
        if (i + 1 >= tokens.length || tokens[i + 1].kind != _TokenKind.string) {
          continue;
        }

        final keyword = token.value;
        final uriToken = tokens[i + 1];
        directives.add(
          _DirectiveUri(
            keyword: keyword,
            uri: uriToken.value,
            line: uriToken.line,
          ),
        );

        // Scan the remainder of the directive until `;` to capture any
        // conditional `if (...) 'uri'` branches cleanly.
        var j = i + 2;
        var dirParenDepth = 0;
        while (j < tokens.length) {
          final next = tokens[j];
          if (next.kind == _TokenKind.semicolon && dirParenDepth == 0) {
            break;
          }
          if (next.kind == _TokenKind.lbrace) {
            // Defensive break if a directive was malformed before a body block.
            break;
          }
          if (next.kind == _TokenKind.lparen) {
            dirParenDepth++;
          } else if (next.kind == _TokenKind.rparen) {
            if (dirParenDepth > 0) dirParenDepth--;
          } else if (next.kind == _TokenKind.string && dirParenDepth == 0) {
            directives.add(
              _DirectiveUri(keyword: keyword, uri: next.value, line: next.line),
            );
          }
          j++;
        }
        i = j;
      case _TokenKind.string:
      case _TokenKind.semicolon:
      case _TokenKind.other:
        break;
    }
  }

  return directives;
}

enum _TokenKind {
  word,
  string,
  semicolon,
  lparen,
  rparen,
  lbrace,
  rbrace,
  lbracket,
  rbracket,
  other,
}

final class _Token {
  final _TokenKind kind;
  final String value;
  final int line;

  const _Token(this.kind, this.value, this.line);
}

final class _DartLexer {
  static const int _chNewline = 0x0A;
  static const int _chReturn = 0x0D;
  static const int _chDoubleQuote = 0x22;
  static const int _chDollar = 0x24;
  static const int _chSingleQuote = 0x27;
  static const int _chLParen = 0x28;
  static const int _chRParen = 0x29;
  static const int _chStar = 0x2A;
  static const int _chSlash = 0x2F;
  static const int _chSemicolon = 0x3B;
  static const int _chLBracket = 0x5B;
  static const int _chBackslash = 0x5C;
  static const int _chRBracket = 0x5D;
  static const int _chLowerR = 0x72;
  static const int _chLBrace = 0x7B;
  static const int _chRBrace = 0x7D;

  final String _source;
  final int _len;
  int _pos = 0;
  int _line = 1;

  _DartLexer(this._source) : _len = _source.length;

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    while (_pos < _len) {
      final ch = _source.codeUnitAt(_pos);

      // Whitespace
      if (_isWhitespace(ch)) {
        _advanceChar();
        continue;
      }

      // Comments
      if (ch == _chSlash && _pos + 1 < _len) {
        final next = _source.codeUnitAt(_pos + 1);
        if (next == _chSlash) {
          _skipLineComment();
          continue;
        }
        if (next == _chStar) {
          _skipBlockComment();
          continue;
        }
      }

      // Raw strings: r'...' / r"..." / r'''...''' / r"""..."""
      if (ch == _chLowerR && _pos + 1 < _len) {
        final next = _source.codeUnitAt(_pos + 1);
        if (next == _chSingleQuote || next == _chDoubleQuote) {
          final startLine = _line;
          _pos++; // consume 'r'
          final value = _readString(isRaw: true, quoteUnit: next);
          tokens.add(_Token(_TokenKind.string, value, startLine));
          continue;
        }
      }

      // Strings: '...' / "..." / '''...''' / """..."""
      if (ch == _chSingleQuote || ch == _chDoubleQuote) {
        final startLine = _line;
        final value = _readString(isRaw: false, quoteUnit: ch);
        tokens.add(_Token(_TokenKind.string, value, startLine));
        continue;
      }

      // Identifiers / keywords
      if (_isIdentStart(ch)) {
        final start = _pos;
        final startLine = _line;
        _pos++;
        while (_pos < _len && _isIdentPart(_source.codeUnitAt(_pos))) {
          _pos++;
        }
        tokens.add(
          _Token(_TokenKind.word, _source.substring(start, _pos), startLine),
        );
        continue;
      }

      // Structural punctuation
      final line = _line;
      _pos++;
      switch (ch) {
        case _chSemicolon:
          tokens.add(_Token(_TokenKind.semicolon, ';', line));
        case _chLParen:
          tokens.add(_Token(_TokenKind.lparen, '(', line));
        case _chRParen:
          tokens.add(_Token(_TokenKind.rparen, ')', line));
        case _chLBrace:
          tokens.add(_Token(_TokenKind.lbrace, '{', line));
        case _chRBrace:
          tokens.add(_Token(_TokenKind.rbrace, '}', line));
        case _chLBracket:
          tokens.add(_Token(_TokenKind.lbracket, '[', line));
        case _chRBracket:
          tokens.add(_Token(_TokenKind.rbracket, ']', line));
        default:
          tokens.add(_Token(_TokenKind.other, '', line));
      }
    }
    return tokens;
  }

  void _advanceChar() {
    final ch = _source.codeUnitAt(_pos++);
    if (ch == _chNewline) {
      _line++;
    } else if (ch == _chReturn) {
      if (_pos < _len && _source.codeUnitAt(_pos) == _chNewline) {
        _pos++;
      }
      _line++;
    }
  }

  void _skipLineComment() {
    _pos += 2;
    while (_pos < _len) {
      final ch = _source.codeUnitAt(_pos);
      if (ch == _chNewline || ch == _chReturn) {
        _advanceChar();
        return;
      }
      _pos++;
    }
  }

  void _skipBlockComment() {
    _pos += 2;
    var depth = 1;
    while (_pos < _len && depth > 0) {
      final ch = _source.codeUnitAt(_pos);
      if (ch == _chSlash &&
          _pos + 1 < _len &&
          _source.codeUnitAt(_pos + 1) == _chStar) {
        depth++;
        _pos += 2;
        continue;
      }
      if (ch == _chStar &&
          _pos + 1 < _len &&
          _source.codeUnitAt(_pos + 1) == _chSlash) {
        depth--;
        _pos += 2;
        continue;
      }
      _advanceChar();
    }
  }

  String _readString({required bool isRaw, required int quoteUnit}) {
    final isTriple =
        _pos + 2 < _len &&
        _source.codeUnitAt(_pos + 1) == quoteUnit &&
        _source.codeUnitAt(_pos + 2) == quoteUnit;
    _pos += isTriple ? 3 : 1;

    final buf = StringBuffer();
    while (_pos < _len) {
      final ch = _source.codeUnitAt(_pos);

      if (isTriple) {
        if (ch == quoteUnit &&
            _pos + 2 < _len &&
            _source.codeUnitAt(_pos + 1) == quoteUnit &&
            _source.codeUnitAt(_pos + 2) == quoteUnit) {
          // Handle 4 or 5 trailing quotes cleanly (e.g. '''x'''').
          if (_pos + 3 < _len && _source.codeUnitAt(_pos + 3) == quoteUnit) {
            buf.writeCharCode(ch);
            _pos++;
            continue;
          }
          _pos += 3;
          break;
        }
      } else {
        if (ch == quoteUnit) {
          _pos++;
          break;
        }
        if (ch == _chNewline || ch == _chReturn) {
          // Unterminated single-line string; stop without swallowing next lines.
          break;
        }
      }

      if (!isRaw && ch == _chBackslash) {
        _pos++;
        if (_pos < _len) {
          final escaped = _source.codeUnitAt(_pos);
          if (escaped == _chNewline || escaped == _chReturn) {
            _advanceChar();
          } else {
            buf.writeCharCode(escaped);
            _pos++;
          }
        }
        continue;
      }

      if (!isRaw &&
          ch == _chDollar &&
          _pos + 1 < _len &&
          _source.codeUnitAt(_pos + 1) == _chLBrace) {
        _pos += 2;
        _skipBracedInterpolation();
        continue;
      }

      if (ch == _chNewline || ch == _chReturn) {
        buf.write('\n');
        _advanceChar();
      } else {
        buf.writeCharCode(ch);
        _pos++;
      }
    }
    return buf.toString();
  }

  void _skipBracedInterpolation() {
    var depth = 1;
    while (_pos < _len && depth > 0) {
      final ch = _source.codeUnitAt(_pos);
      if (_isWhitespace(ch)) {
        _advanceChar();
        continue;
      }
      if (ch == _chSlash && _pos + 1 < _len) {
        final next = _source.codeUnitAt(_pos + 1);
        if (next == _chSlash) {
          _skipLineComment();
          continue;
        }
        if (next == _chStar) {
          _skipBlockComment();
          continue;
        }
      }
      if (ch == _chLowerR && _pos + 1 < _len) {
        final next = _source.codeUnitAt(_pos + 1);
        if (next == _chSingleQuote || next == _chDoubleQuote) {
          _pos++;
          _readString(isRaw: true, quoteUnit: next);
          continue;
        }
      }
      if (ch == _chSingleQuote || ch == _chDoubleQuote) {
        _readString(isRaw: false, quoteUnit: ch);
        continue;
      }
      if (ch == _chLBrace) {
        depth++;
      } else if (ch == _chRBrace) {
        depth--;
      }
      _pos++;
    }
  }

  static bool _isWhitespace(int ch) =>
      ch == 0x20 ||
      ch == 0x09 ||
      ch == 0x0A ||
      ch == 0x0D ||
      ch == 0x0B ||
      ch == 0x0C;

  static bool _isIdentStart(int ch) =>
      (ch >= 0x41 && ch <= 0x5A) || // A-Z
      (ch >= 0x61 && ch <= 0x7A) || // a-z
      ch == 0x5F || // _
      ch == 0x24; // $

  static bool _isIdentPart(int ch) =>
      _isIdentStart(ch) || (ch >= 0x30 && ch <= 0x39); // 0-9
}
