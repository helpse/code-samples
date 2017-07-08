import { fromJS } from 'immutable';

import actions from '../../constants/planificacion';
const {
  FICHA_FIRMA_UPDATE,

  DIMENSION_UPDATE,

  FACTOR_UPDATE,
  FACTOR_TOGGLE_HIDE,

  ACTIVIDAD_ADD,
  ACTIVIDAD_REMOVE,
  ACTIVIDAD_UPDATE,

  ACTIVIDAD_ESTANDAR_ADD,
  ACTIVIDAD_ESTANDAR_REMOVE,
  ACTIVIDAD_ESTANDAR_UPDATE,

  ESTANDAR_DECREMENT,
  ESTANDAR_INCREMENT,
} = actions;

import nodoActions from '../../constants/status';
const {
  NODO_VALIDATION_ERROR,
  NODO_FETCHING,
  NODO_STORED,
  NODO_SERVER_ERROR,
  NODO_SUCCESS,
  UPDATE_REQUEST_TYPE,
} = nodoActions;

import status from '../status';
import dimensiones from './dimensiones';
import factores from './factores';
import actividades from './actividades';
import estandares from './estandares';
import ficha from './ficha';

export default (
  state,
  action
) => {
  let newState = state;

  switch (action.type) {
    case UPDATE_REQUEST_TYPE:
      return newState.set('requestType', action.request);

    case NODO_STORED:
      newState = newState
        .setIn([...action.path, 'dbId'], action.dbId);
    case NODO_SUCCESS:
    case NODO_VALIDATION_ERROR:
    case NODO_FETCHING:
    case NODO_SERVER_ERROR:
      return newState
        .setIn(
          [...action.path, 'status'],
          status(state.getIn([...action.path, 'status']), action)
        );

    case FICHA_FIRMA_UPDATE:
      return state
        .set(
          'fic',
          ficha(state.get('fic'), action)
        );

    case DIMENSION_UPDATE:
      return state
        .set(
          'dim',
          dimensiones(state.get('dim'), action)
        );

    case FACTOR_TOGGLE_HIDE:
    case FACTOR_UPDATE:
      return state
        .set(
          'fac',
          factores(state.get('fac'), action)
        );

    case ACTIVIDAD_ADD:
    case ACTIVIDAD_REMOVE:
    case ACTIVIDAD_UPDATE:
    case ACTIVIDAD_ESTANDAR_ADD:
    case ACTIVIDAD_ESTANDAR_REMOVE:
    case ACTIVIDAD_ESTANDAR_UPDATE:
      return state
        .set(
          'act',
          actividades(state.get('act'), action)
        );

    case ESTANDAR_INCREMENT:
    case ESTANDAR_DECREMENT:
      return state
        .set(
          'estandares',
          estandares(state.get('estandares'), action)
        );

    default:
      return state;
  }
};
