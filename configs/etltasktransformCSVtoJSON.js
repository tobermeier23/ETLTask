/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

function transformCSVtoJSON(line) {
    var values = line.split(',');
    var properties = [
      'observation_date',
      'icsa',
    ];
    var etltaskicsa = {};
  
    for (var count = 0; count < values.length; count++) {
      if (values[count] !== 'null') {
        etltaskicsa[properties[count]] = values[count];
      }
    }
  
    var jsonString = JSON.stringify(etltaskicsa);
    return jsonString;
  }