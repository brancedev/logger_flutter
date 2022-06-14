part of logger_flutter;

class _WrappedOutput implements LogOutput {
  final Function(OutputEvent e) outputListener;
  final LogOutput innerLogOutput;

  _WrappedOutput(this.outputListener, this.innerLogOutput);

  @override
  void output(OutputEvent event) {
    innerLogOutput.output(event);
    outputListener(event);
  }

  @override
  void destroy() {
    innerLogOutput.destroy();
  }

  @override
  void init() {
    innerLogOutput.init();
  }
}

class LogConsole extends StatefulWidget {
  final bool showCloseButton;

  static ListQueue<OutputEvent> _outputEventBuffer = ListQueue();
  static bool _initialized = false;
  static final _newLogs = ChangeNotifier();

  LogConsole({this.showCloseButton = false})
      : assert(_initialized, 'Please call LogConsole.init() first.');

  /// Attach this LogOutput to your logger instance:
  /// `
  /// Logger(
  ///     printer: PrettyPrinter(
  ///       printTime: true,
  ///       printEmojis: true,
  ///       colors: true,
  ///       methodCount: methodCount,
  ///       errorMethodCount: errMethodCount,
  ///     ),
  ///     level: level,
  ///     output: LogConsole.wrap(output),
  ///     filter: ProductionFiler(),
  ///   );
  /// `
  static LogOutput wrap({int bufferSize = 1000, LogOutput? innerOutput}) {
    _initialized = true;

    final output = innerOutput ?? ConsoleOutput();

    return _WrappedOutput((e) {
      if (_outputEventBuffer.length == bufferSize) {
        _outputEventBuffer.removeFirst();
      }
      _outputEventBuffer.add(e);
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      _newLogs.notifyListeners();
    }, output);
  }

  @override
  _LogConsoleState createState() => _LogConsoleState();

  static void openLogConsole(BuildContext context) async {
    var logConsole = LogConsole(
      showCloseButton: true,
    );
    PageRoute route;
    route = MaterialPageRoute(builder: (_) => logConsole);

    await Navigator.push(context, route);
  }
}

class RenderedEvent {
  final int id;
  final Level level;
  final String text;

  RenderedEvent(this.id, this.level, this.text);
}

class _LogConsoleState extends State<LogConsole> {
  final ListQueue<RenderedEvent> _renderedBuffer = ListQueue();
  List<RenderedEvent> _filteredBuffer = [];

  final _scrollController = ScrollController();
  final _filterController = TextEditingController();

  Level _filterLevel = Level.verbose;
  double _logFontSize = 14;

  var _currentId = 0;
  bool _scrollListenerEnabled = true;
  bool _followBottom = true;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
      if (!_scrollListenerEnabled) return;
      var scrolledToBottom = _scrollController.offset >=
          _scrollController.position.maxScrollExtent;
      setState(() {
        _followBottom = scrolledToBottom;
      });
    });

    LogConsole._newLogs.addListener(_onNewLogs);
  }

  void _onNewLogs() {
    setState(() {
      _reloadContent();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _reloadContent();
  }

  void _reloadContent() {
    _renderedBuffer.clear();
    for (var event in LogConsole._outputEventBuffer) {
      _renderedBuffer.add(_renderEvent(event));
    }
    _refreshFilter();
  }

  void _refreshFilter() {
    var newFilteredBuffer = _renderedBuffer.where((it) {
      var logLevelMatches = it.level.index >= _filterLevel.index;
      if (!logLevelMatches) {
        return false;
      } else if (_filterController.text.isNotEmpty) {
        var filterText = _filterController.text.toLowerCase();
        return it.text.toLowerCase().contains(filterText);
      } else {
        return true;
      }
    }).toList();
    setState(() {
      _filteredBuffer = newFilteredBuffer;
    });

    if (_followBottom) {
      Future.delayed(Duration.zero, _scrollToBottom);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blueGrey,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildTopBar(),
              Expanded(
                child: _buildLogContent(),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
        floatingActionButton: AnimatedOpacity(
          opacity: _followBottom ? 0 : 1,
          duration: Duration(milliseconds: 150),
          child: Padding(
            padding: EdgeInsets.only(bottom: 60),
            child: FloatingActionButton(
              mini: true,
              clipBehavior: Clip.antiAlias,
              child: Icon(
                Icons.arrow_downward,
                color: Colors.lightBlue[900],
              ),
              onPressed: _scrollToBottom,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogContent() {
    StringBuffer text = _bufferToString();

    return Container(
      color: Colors.black,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        controller: _scrollController,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1600,
            child: SelectableText(
              text.toString(),
              style: TextStyle(
                fontSize: _logFontSize,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  StringBuffer _bufferToString() {
    final text = StringBuffer();
    _filteredBuffer.forEach((e) {
      text.write(e.text);
      text.write('\n');
    });
    return text;
  }

  Widget _buildTopBar() {
    return LogBar(
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Text(
            'Logs',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Spacer(),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () {
              setState(() {
                _logFontSize++;
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.remove),
            onPressed: () {
              setState(() {
                _logFontSize--;
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.copy_all),
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: _bufferToString().toString(),
                ),
              );
            },
          ),
          if (widget.showCloseButton)
            IconButton(
              icon: Icon(Icons.close),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return LogBar(
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Expanded(
            child: TextField(
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
              ),
              controller: _filterController,
              onChanged: (s) => _refreshFilter(),
              decoration: InputDecoration(
                labelText: 'Filter log output',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          SizedBox(width: 20),
          DropdownButton(
            value: _filterLevel,
            items: [
              DropdownMenuItem(
                child: Text('VERBOSE'),
                value: Level.verbose,
              ),
              DropdownMenuItem(
                child: Text(
                  PrettyPrinter.levelEmojis[Level.debug]! + ' DEBUG',
                ),
                value: Level.debug,
              ),
              DropdownMenuItem(
                child: Text(
                  PrettyPrinter.levelEmojis[Level.info]! + ' INFO',
                ),
                value: Level.info,
              ),
              DropdownMenuItem(
                child: Text(
                  PrettyPrinter.levelEmojis[Level.warning]! + ' WARNING',
                ),
                value: Level.warning,
              ),
              DropdownMenuItem(
                child: Text(
                  PrettyPrinter.levelEmojis[Level.error]! + ' ERROR',
                ),
                value: Level.error,
              ),
            ],
            onChanged: (value) {
              _filterLevel = value as Level;
              _refreshFilter();
            },
          )
        ],
      ),
    );
  }

  void _scrollToBottom() async {
    _scrollListenerEnabled = false;

    setState(() {
      _followBottom = true;
    });

    var scrollPosition = _scrollController.position;
    await _scrollController.animateTo(
      scrollPosition.maxScrollExtent,
      duration: Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );

    _scrollListenerEnabled = true;
  }

  RenderedEvent _renderEvent(OutputEvent event) {
    var text = event.lines.join('\n');
    return RenderedEvent(
      _currentId++,
      event.level,
      text,
    );
  }

  @override
  void dispose() {
    LogConsole._newLogs.removeListener(_onNewLogs);
    super.dispose();
  }
}

class LogBar extends StatelessWidget {
  final Widget child;

  LogBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [],
        ),
        child: Material(
          color: Colors.blueGrey[900],
          child: Padding(
            padding: EdgeInsets.fromLTRB(15, 8, 15, 8),
            child: child,
          ),
        ),
      ),
    );
  }
}
