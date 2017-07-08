import { fromJS } from 'immutable';

import constantsExpInteres from '../../constants/expresionInteres';

import {
  fichaValidation,
  institucionalValidation,
  carreraValidation,
} from '../../validations/expresionInteres';

import {
  validateInlineErrors,
} from '../../utils';

import {
  APIstoreNodo,
  APIfinish,
} from '../../webAPI/expresionInteres';

import {
  storeNodo,
  notValidated,
  updateRequestType,
} from '../../actions/aNodoStatus';

import {
  getContext,
} from '../../context';

import constants from '../../constants/status';
const {
  STORED_OK,
  REQUEST_SAVE_ALL,
} = constants;

const getPaths = (state) =>
  [
    ['fic'],
    ['ins'],
    ...state.get('car').map((_, i) => ['car', i])
  ];

const displayErrors = ({
  dispatch,
  paths,
  errors,
}) =>
  errors.forEach((error, i) =>
    dispatch(notValidated(paths[i], error)));

const hasErrorAndDisplay = ({
  dispatch,
  state,
}) => {
  const paths = getPaths(state);
  let validInlineFichas = [
    validateInlineErrors(document.getElementById(paths[0].join(''))),
    validateInlineErrors(document.getElementById(paths[1].join(''))),
      ...state.get('car')
      .map((_, i) =>
           validateInlineErrors(document.getElementById(`car${i}`)))
  ];

  const errorMsg = 'Existen campos que no cumplen con los valores permitidos';

  const inlineErrors = validInlineFichas
    .map(isValid => {
      if (!isValid) {
        return [errorMsg];
      }
      return [];
    });
  let validationErrors = [
    fichaValidation(state),
    institucionalValidation(state),
      ...state.get('car').map(carreraValidation)
  ];

  const mixedErrors = inlineErrors
    .map((errors, i) => errors.concat(validationErrors[i]));

  displayErrors({ dispatch, paths, errors: mixedErrors });

  const cannotFinish = _.filter(mixedErrors, errors => errors.length).length;

  return cannotFinish;
};

export const finishFicha = (status) =>
  (dispatch, getState) => {

    const cannotFinish = hasErrorAndDisplay({
      dispatch,
      state: getState()
    });

    if (status !== STORED_OK) {
      return saveAllNodes({
        dispatch,
        state: getState(),
      });
    }

    if (cannotFinish) {
      return;
    }

    console.log('to finish');
    APIfinish();

  };


const saveAllNodes = ({
  dispatch,
  state,
}) => {
  const paths = getPaths(state);
  const nodesToSave = paths
          .filter(path =>
                  state.getIn([...path, 'status', 'status']) !== 'FETCHING' &&
                  state.getIn([...path, 'status', 'hasChanged']));

  dispatch(updateRequestType(REQUEST_SAVE_ALL));
  nodesToSave
    .forEach(path => dispatch(storeNodo({ path, webAPI: APIstoreNodo })));

};

export const showErrorsAndSaveAllNodes = () =>
  (dispatch, getState) => {
    hasErrorAndDisplay({
      dispatch,
      state: getState()
    });

    saveAllNodes({
      dispatch,
      state: getState(),
    });
  };
