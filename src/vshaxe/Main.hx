package vshaxe;

import vshaxe.commands.Commands;
import vshaxe.commands.InitProject;
import vshaxe.configuration.HaxeInstallation;
import vshaxe.display.DisplayArguments;
import vshaxe.display.DisplayArgumentsSelector;
import vshaxe.display.HaxeDisplayArgumentsProvider;
import vshaxe.helper.HaxeCodeLensProvider;
import vshaxe.helper.HxmlParser;
import vshaxe.server.LanguageServer;
import vshaxe.tasks.HaxeTaskProvider;
import vshaxe.tasks.HxmlTaskProvider;
import vshaxe.tasks.TaskConfiguration;
import vshaxe.view.HaxeServerViewContainer;
import vshaxe.view.dependencies.DependencyTreeView;

class Main {
	var api:Vshaxe;

	function new(context:ExtensionContext) {
		new InitProject(context);
		new AutoIndentation(context);

		var folder = if (workspace.workspaceFolders == null) null else workspace.workspaceFolders[0];
		if (folder == null)
			return; // TODO: look into this - we could support _some_ nice functionality (e.g. std lib completion or --interp task)

		var mementos = new WorkspaceMementos(context.workspaceState);

		var hxmlDiscovery = new HxmlDiscovery(folder, mementos);
		context.subscriptions.push(hxmlDiscovery);

		var displayArguments = new DisplayArguments(folder, mementos);
		context.subscriptions.push(displayArguments);

		var haxeInstallation = new HaxeInstallation(folder, mementos);
		context.subscriptions.push(haxeInstallation);

		var problemMatchers = ["$haxe-absolute", "$haxe", "$haxe-error", "$haxe-trace"];
		api = {
			haxeExecutable: haxeInstallation.haxe,
			enableCompilationServer: true,
			problemMatchers: problemMatchers.copy(),
			taskPresentation: {},
			registerDisplayArgumentsProvider: displayArguments.registerProvider,
			registerHaxeInstallationProvider: haxeInstallation.registerProvider,
			parseHxmlToArguments: HxmlParser.parseToArgs
		};

		var server = new LanguageServer(folder, context, haxeInstallation, displayArguments, api);
		context.subscriptions.push(server);

		new HaxeCodeLensProvider();
		new HaxeServerViewContainer(context, server);
		new DependencyTreeView(context, displayArguments, haxeInstallation);
		new EvalDebugger(displayArguments, haxeInstallation.haxe);
		new DisplayArgumentsSelector(context, displayArguments);
		var haxeDisplayArgumentsProvider = new HaxeDisplayArgumentsProvider(context, displayArguments, hxmlDiscovery);
		new Commands(context, server, haxeDisplayArgumentsProvider);
		new ExtensionRecommender(context, folder).run();

		var taskConfiguration = new TaskConfiguration(haxeInstallation, problemMatchers, server, api);
		new HxmlTaskProvider(taskConfiguration, hxmlDiscovery);
		new HaxeTaskProvider(taskConfiguration, displayArguments, haxeDisplayArgumentsProvider);

		scheduleStartup(displayArguments, haxeInstallation, server);
	}

	function scheduleStartup(displayArguments:DisplayArguments, haxeInstallation:HaxeInstallation, server:LanguageServer) {
		// wait until we have the providers we need to avoid immediate server restarts
		var waitingForDisplayArguments = displayArguments.isWaitingForProvider();
		var waitingForInstallation = haxeInstallation.isWaitingForProvider();
		var haxeFileOpened = false;

		var started = false;
		var disposables = [];
		function maybeStartServer() {
			if (!waitingForInstallation && (!waitingForDisplayArguments || haxeFileOpened) && !started) {
				disposables.iter(d -> d.dispose());
				started = true;
				commands.executeCommand("setContext", "vshaxeActivated", true);
				server.start();
			}
		}
		if (waitingForDisplayArguments) {
			disposables.push(displayArguments.onDidChangeArguments(_ -> {
				waitingForDisplayArguments = false;
				maybeStartServer();
			}));
			disposables.push(workspace.onDidOpenTextDocument(function(document) {
				if (document.languageId == "haxe") {
					haxeFileOpened = true;
					maybeStartServer();
				}
			}));
		}
		if (waitingForInstallation) {
			disposables.push(haxeInstallation.onDidChange(_ -> {
				waitingForInstallation = false;
				maybeStartServer();
			}));
		}

		// maybe we're ready right away
		maybeStartServer();
	}

	@:expose("activate")
	static function main(context:ExtensionContext) {
		return new Main(context).api;
	}
}
