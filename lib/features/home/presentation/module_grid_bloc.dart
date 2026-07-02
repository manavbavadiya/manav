import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/module_remote_datasource.dart';
import '../domain/odoo_module.dart';

abstract class ModuleGridEvent extends Equatable {
  const ModuleGridEvent();
  @override
  List<Object?> get props => const [];
}

class LoadModules extends ModuleGridEvent {
  const LoadModules();
}

abstract class ModuleGridState extends Equatable {
  const ModuleGridState();
  @override
  List<Object?> get props => const [];
}

class ModuleGridInitial extends ModuleGridState {
  const ModuleGridInitial();
}

class ModuleGridLoading extends ModuleGridState {
  const ModuleGridLoading();
}

class ModuleGridLoaded extends ModuleGridState {
  const ModuleGridLoaded(this.modules);
  final List<OdooModule> modules;

  @override
  List<Object?> get props => [modules];
}

class ModuleGridError extends ModuleGridState {
  const ModuleGridError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class ModuleGridBloc extends Bloc<ModuleGridEvent, ModuleGridState> {
  ModuleGridBloc(this._ds) : super(const ModuleGridInitial()) {
    on<LoadModules>(_onLoad);
  }
  final ModuleRemoteDataSource _ds;

  Future<void> _onLoad(LoadModules e, Emitter<ModuleGridState> emit) async {
    emit(const ModuleGridLoading());
    final modules = await _ds.getModuleTree();
    emit(ModuleGridLoaded(modules));
  }
}
