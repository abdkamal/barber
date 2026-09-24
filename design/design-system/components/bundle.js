/* @ds-bundle: {"format": 4, "namespace": "Saloni", "components": [{"name": "Icon"}, {"name": "Button"}, {"name": "TextField"}, {"name": "SegmentedControl"}, {"name": "ServiceChip"}, {"name": "StatusBadge"}, {"name": "Avatar"}, {"name": "BarberOption"}, {"name": "EtaCard"}, {"name": "QueueItem"}, {"name": "CurrentServiceCard"}, {"name": "OfferCard"}, {"name": "ImpactList"}, {"name": "Banner"}, {"name": "ConnectionBar"}, {"name": "Switch"}, {"name": "StatTile"}, {"name": "BottomNav"}, {"name": "EmptyState"}, {"name": "CatalogItem"}, {"name": "HoursList"}, {"name": "ContactBar"}]} */

(function(){
var R = window.React, h = R.createElement, useState = R.useState;
var ICONS = {"scissors": "<path d=\"M157.73,113.13A8,8,0,0,1,159.82,102L227.48,55.7a8,8,0,0,1,9,13.21l-67.67,46.3a7.92,7.92,0,0,1-4.51,1.4A8,8,0,0,1,157.73,113.13Zm80.87,85.09a8,8,0,0,1-11.12,2.08L136,137.7,93.49,166.78a36,36,0,1,1-9-13.19L121.83,128,84.44,102.41a35.86,35.86,0,1,1,9-13.19l143,97.87A8,8,0,0,1,238.6,198.22ZM80,180a20,20,0,1,0-5.86,14.14A19.85,19.85,0,0,0,80,180ZM74.14,90.13a20,20,0,1,0-28.28,0A19.85,19.85,0,0,0,74.14,90.13Z\"/>", "clock": "<path d=\"M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216Zm64-88a8,8,0,0,1-8,8H128a8,8,0,0,1-8-8V72a8,8,0,0,1,16,0v48h48A8,8,0,0,1,192,128Z\"/>", "hourglass-medium": "<path d=\"M200,75.64V40a16,16,0,0,0-16-16H72A16,16,0,0,0,56,40V76a16.07,16.07,0,0,0,6.4,12.8L114.67,128,62.4,167.2A16.07,16.07,0,0,0,56,180v36a16,16,0,0,0,16,16H184a16,16,0,0,0,16-16V180.36a16.09,16.09,0,0,0-6.35-12.77L141.27,128l52.38-39.6A16.05,16.05,0,0,0,200,75.64ZM72,40H184V75.64L178.23,80H77.33L72,76Zm56,78L98.67,96h58.4Zm56,98H72V180l48-36v24a8,8,0,0,0,16,0V144.08l48,36.28Z\"/>", "user": "<path d=\"M230.92,212c-15.23-26.33-38.7-45.21-66.09-54.16a72,72,0,1,0-73.66,0C63.78,166.78,40.31,185.66,25.08,212a8,8,0,1,0,13.85,8c18.84-32.56,52.14-52,89.07-52s70.23,19.44,89.07,52a8,8,0,1,0,13.85-8ZM72,96a56,56,0,1,1,56,56A56.06,56.06,0,0,1,72,96Z\"/>", "users-three": "<path d=\"M244.8,150.4a8,8,0,0,1-11.2-1.6A51.6,51.6,0,0,0,192,128a8,8,0,0,1-7.37-4.89,8,8,0,0,1,0-6.22A8,8,0,0,1,192,112a24,24,0,1,0-23.24-30,8,8,0,1,1-15.5-4A40,40,0,1,1,219,117.51a67.94,67.94,0,0,1,27.43,21.68A8,8,0,0,1,244.8,150.4ZM190.92,212a8,8,0,1,1-13.84,8,57,57,0,0,0-98.16,0,8,8,0,1,1-13.84-8,72.06,72.06,0,0,1,33.74-29.92,48,48,0,1,1,58.36,0A72.06,72.06,0,0,1,190.92,212ZM128,176a32,32,0,1,0-32-32A32,32,0,0,0,128,176ZM72,120a8,8,0,0,0-8-8A24,24,0,1,1,87.24,82a8,8,0,1,0,15.5-4A40,40,0,1,0,37,117.51,67.94,67.94,0,0,0,9.6,139.19a8,8,0,1,0,12.8,9.61A51.6,51.6,0,0,1,64,128,8,8,0,0,0,72,120Z\"/>", "calendar-check": "<path d=\"M208,32H184V24a8,8,0,0,0-16,0v8H88V24a8,8,0,0,0-16,0v8H48A16,16,0,0,0,32,48V208a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V48A16,16,0,0,0,208,32ZM72,48v8a8,8,0,0,0,16,0V48h80v8a8,8,0,0,0,16,0V48h24V80H48V48ZM208,208H48V96H208V208Zm-38.34-85.66a8,8,0,0,1,0,11.32l-48,48a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L116,164.69l42.34-42.35A8,8,0,0,1,169.66,122.34Z\"/>", "bell-ringing": "<path d=\"M224,71.1a8,8,0,0,1-10.78-3.42,94.13,94.13,0,0,0-33.46-36.91,8,8,0,1,1,8.54-13.54,111.46,111.46,0,0,1,39.12,43.09A8,8,0,0,1,224,71.1ZM35.71,72a8,8,0,0,0,7.1-4.32A94.13,94.13,0,0,1,76.27,30.77a8,8,0,1,0-8.54-13.54A111.46,111.46,0,0,0,28.61,60.32,8,8,0,0,0,35.71,72Zm186.1,103.94A16,16,0,0,1,208,200H167.2a40,40,0,0,1-78.4,0H48a16,16,0,0,1-13.79-24.06C43.22,160.39,48,138.28,48,112a80,80,0,0,1,160,0C208,138.27,212.78,160.38,221.81,175.94ZM150.62,200H105.38a24,24,0,0,0,45.24,0ZM208,184c-10.64-18.27-16-42.49-16-72a64,64,0,0,0-128,0c0,29.52-5.38,53.74-16,72Z\"/>", "wifi-slash": "<path d=\"M213.92,210.62a8,8,0,1,1-11.84,10.76l-52-57.15a60,60,0,0,0-57.41,7.24,8,8,0,1,1-9.42-12.93A75.43,75.43,0,0,1,128,144c1.28,0,2.55,0,3.82.1L104.9,114.49A108,108,0,0,0,61,135.31,8,8,0,0,1,49.73,134,8,8,0,0,1,51,122.77a124.27,124.27,0,0,1,41.71-21.66L69.37,75.4a155.43,155.43,0,0,0-40.29,24A8,8,0,0,1,18.92,87,171.87,171.87,0,0,1,58,62.86L42.08,45.38A8,8,0,1,1,53.92,34.62ZM128,192a12,12,0,1,0,12,12A12,12,0,0,0,128,192ZM237.08,87A172.3,172.3,0,0,0,106,49.4a8,8,0,1,0,2,15.87A158.33,158.33,0,0,1,128,64a156.25,156.25,0,0,1,98.92,35.37A8,8,0,0,0,237.08,87ZM195,135.31a8,8,0,0,0,11.24-1.3,8,8,0,0,0-1.3-11.24,124.25,124.25,0,0,0-51.73-24.2A8,8,0,1,0,150,114.24,108.12,108.12,0,0,1,195,135.31Z\"/>", "wifi-high": "<path d=\"M140,204a12,12,0,1,1-12-12A12,12,0,0,1,140,204ZM237.08,87A172,172,0,0,0,18.92,87,8,8,0,0,0,29.08,99.37a156,156,0,0,1,197.84,0A8,8,0,0,0,237.08,87ZM205,122.77a124,124,0,0,0-153.94,0A8,8,0,0,0,61,135.31a108,108,0,0,1,134.06,0,8,8,0,0,0,11.24-1.3A8,8,0,0,0,205,122.77Zm-32.26,35.76a76.05,76.05,0,0,0-89.42,0,8,8,0,0,0,9.42,12.94,60,60,0,0,1,70.58,0,8,8,0,1,0,9.42-12.94Z\"/>", "check": "<path d=\"M229.66,77.66l-128,128a8,8,0,0,1-11.32,0l-56-56a8,8,0,0,1,11.32-11.32L96,188.69,218.34,66.34a8,8,0,0,1,11.32,11.32Z\"/>", "check-circle": "<path d=\"M173.66,98.34a8,8,0,0,1,0,11.32l-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35A8,8,0,0,1,173.66,98.34ZM232,128A104,104,0,1,1,128,24,104.11,104.11,0,0,1,232,128Zm-16,0a88,88,0,1,0-88,88A88.1,88.1,0,0,0,216,128Z\"/>", "x": "<path d=\"M205.66,194.34a8,8,0,0,1-11.32,11.32L128,139.31,61.66,205.66a8,8,0,0,1-11.32-11.32L116.69,128,50.34,61.66A8,8,0,0,1,61.66,50.34L128,116.69l66.34-66.35a8,8,0,0,1,11.32,11.32L139.31,128Z\"/>", "x-circle": "<path d=\"M165.66,101.66,139.31,128l26.35,26.34a8,8,0,0,1-11.32,11.32L128,139.31l-26.34,26.35a8,8,0,0,1-11.32-11.32L116.69,128,90.34,101.66a8,8,0,0,1,11.32-11.32L128,116.69l26.34-26.35a8,8,0,0,1,11.32,11.32ZM232,128A104,104,0,1,1,128,24,104.11,104.11,0,0,1,232,128Zm-16,0a88,88,0,1,0-88,88A88.1,88.1,0,0,0,216,128Z\"/>", "caret-left": "<path d=\"M165.66,202.34a8,8,0,0,1-11.32,11.32l-80-80a8,8,0,0,1,0-11.32l80-80a8,8,0,0,1,11.32,11.32L91.31,128Z\"/>", "caret-right": "<path d=\"M181.66,133.66l-80,80a8,8,0,0,1-11.32-11.32L164.69,128,90.34,53.66a8,8,0,0,1,11.32-11.32l80,80A8,8,0,0,1,181.66,133.66Z\"/>", "plus": "<path d=\"M224,128a8,8,0,0,1-8,8H136v80a8,8,0,0,1-16,0V136H40a8,8,0,0,1,0-16h80V40a8,8,0,0,1,16,0v80h80A8,8,0,0,1,224,128Z\"/>", "coins": "<path d=\"M184,89.57V84c0-25.08-37.83-44-88-44S8,58.92,8,84v40c0,20.89,26.25,37.49,64,42.46V172c0,25.08,37.83,44,88,44s88-18.92,88-44V132C248,111.3,222.58,94.68,184,89.57ZM232,132c0,13.22-30.79,28-72,28-3.73,0-7.43-.13-11.08-.37C170.49,151.77,184,139,184,124V105.74C213.87,110.19,232,122.27,232,132ZM72,150.25V126.46A183.74,183.74,0,0,0,96,128a183.74,183.74,0,0,0,24-1.54v23.79A163,163,0,0,1,96,152,163,163,0,0,1,72,150.25Zm96-40.32V124c0,8.39-12.41,17.4-32,22.87V123.5C148.91,120.37,159.84,115.71,168,109.93ZM96,56c41.21,0,72,14.78,72,28s-30.79,28-72,28S24,97.22,24,84,54.79,56,96,56ZM24,124V109.93c8.16,5.78,19.09,10.44,32,13.57v23.37C36.41,141.4,24,132.39,24,124Zm64,48v-4.17c2.63.1,5.29.17,8,.17,3.88,0,7.67-.13,11.39-.35A121.92,121.92,0,0,0,120,171.41v23.46C100.41,189.4,88,180.39,88,172Zm48,26.25V174.4a179.48,179.48,0,0,0,24,1.6,183.74,183.74,0,0,0,24-1.54v23.79a165.45,165.45,0,0,1-48,0Zm64-3.38V171.5c12.91-3.13,23.84-7.79,32-13.57V172C232,180.39,219.59,189.4,200,194.87Z\"/>", "receipt": "<path d=\"M72,104a8,8,0,0,1,8-8h96a8,8,0,0,1,0,16H80A8,8,0,0,1,72,104Zm8,40h96a8,8,0,0,0,0-16H80a8,8,0,0,0,0,16ZM232,56V208a8,8,0,0,1-11.58,7.15L192,200.94l-28.42,14.21a8,8,0,0,1-7.16,0L128,200.94,99.58,215.15a8,8,0,0,1-7.16,0L64,200.94,35.58,215.15A8,8,0,0,1,24,208V56A16,16,0,0,1,40,40H216A16,16,0,0,1,232,56Zm-16,0H40V195.06l20.42-10.22a8,8,0,0,1,7.16,0L96,199.06l28.42-14.22a8,8,0,0,1,7.16,0L160,199.06l28.42-14.22a8,8,0,0,1,7.16,0L216,195.06Z\"/>", "chart-bar": "<path d=\"M224,200h-8V40a8,8,0,0,0-8-8H152a8,8,0,0,0-8,8V80H96a8,8,0,0,0-8,8v40H48a8,8,0,0,0-8,8v64H32a8,8,0,0,0,0,16H224a8,8,0,0,0,0-16ZM160,48h40V200H160ZM104,96h40V200H104ZM56,144H88v56H56Z\"/>", "gear-six": "<path d=\"M128,80a48,48,0,1,0,48,48A48.05,48.05,0,0,0,128,80Zm0,80a32,32,0,1,1,32-32A32,32,0,0,1,128,160Zm109.94-52.79a8,8,0,0,0-3.89-5.4l-29.83-17-.12-33.62a8,8,0,0,0-2.83-6.08,111.91,111.91,0,0,0-36.72-20.67,8,8,0,0,0-6.46.59L128,41.85,97.88,25a8,8,0,0,0-6.47-.6A112.1,112.1,0,0,0,54.73,45.15a8,8,0,0,0-2.83,6.07l-.15,33.65-29.83,17a8,8,0,0,0-3.89,5.4,106.47,106.47,0,0,0,0,41.56,8,8,0,0,0,3.89,5.4l29.83,17,.12,33.62a8,8,0,0,0,2.83,6.08,111.91,111.91,0,0,0,36.72,20.67,8,8,0,0,0,6.46-.59L128,214.15,158.12,231a7.91,7.91,0,0,0,3.9,1,8.09,8.09,0,0,0,2.57-.42,112.1,112.1,0,0,0,36.68-20.73,8,8,0,0,0,2.83-6.07l.15-33.65,29.83-17a8,8,0,0,0,3.89-5.4A106.47,106.47,0,0,0,237.94,107.21Zm-15,34.91-28.57,16.25a8,8,0,0,0-3,3c-.58,1-1.19,2.06-1.81,3.06a7.94,7.94,0,0,0-1.22,4.21l-.15,32.25a95.89,95.89,0,0,1-25.37,14.3L134,199.13a8,8,0,0,0-3.91-1h-.19c-1.21,0-2.43,0-3.64,0a8.08,8.08,0,0,0-4.1,1l-28.84,16.1A96,96,0,0,1,67.88,201l-.11-32.2a8,8,0,0,0-1.22-4.22c-.62-1-1.23-2-1.8-3.06a8.09,8.09,0,0,0-3-3.06l-28.6-16.29a90.49,90.49,0,0,1,0-28.26L61.67,97.63a8,8,0,0,0,3-3c.58-1,1.19-2.06,1.81-3.06a7.94,7.94,0,0,0,1.22-4.21l.15-32.25a95.89,95.89,0,0,1,25.37-14.3L122,56.87a8,8,0,0,0,4.1,1c1.21,0,2.43,0,3.64,0a8.08,8.08,0,0,0,4.1-1l28.84-16.1A96,96,0,0,1,188.12,55l.11,32.2a8,8,0,0,0,1.22,4.22c.62,1,1.23,2,1.8,3.06a8.09,8.09,0,0,0,3,3.06l28.6,16.29A90.49,90.49,0,0,1,222.9,142.12Z\"/>", "qr-code": "<path d=\"M104,40H56A16,16,0,0,0,40,56v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V56A16,16,0,0,0,104,40Zm0,64H56V56h48v48Zm0,32H56a16,16,0,0,0-16,16v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V152A16,16,0,0,0,104,136Zm0,64H56V152h48v48ZM200,40H152a16,16,0,0,0-16,16v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V56A16,16,0,0,0,200,40Zm0,64H152V56h48v48Zm-64,72V144a8,8,0,0,1,16,0v32a8,8,0,0,1-16,0Zm80-16a8,8,0,0,1-8,8H184v40a8,8,0,0,1-8,8H144a8,8,0,0,1,0-16h24V144a8,8,0,0,1,16,0v8h24A8,8,0,0,1,216,160Zm0,32v16a8,8,0,0,1-16,0V192a8,8,0,0,1,16,0Z\"/>", "phone": "<path d=\"M222.37,158.46l-47.11-21.11-.13-.06a16,16,0,0,0-15.17,1.4,8.12,8.12,0,0,0-.75.56L134.87,160c-15.42-7.49-31.34-23.29-38.83-38.51l20.78-24.71c.2-.25.39-.5.57-.77a16,16,0,0,0,1.32-15.06l0-.12L97.54,33.64a16,16,0,0,0-16.62-9.52A56.26,56.26,0,0,0,32,80c0,79.4,64.6,144,144,144a56.26,56.26,0,0,0,55.88-48.92A16,16,0,0,0,222.37,158.46ZM176,208A128.14,128.14,0,0,1,48,80,40.2,40.2,0,0,1,82.87,40a.61.61,0,0,0,0,.12l21,47L83.2,111.86a6.13,6.13,0,0,0-.57.77,16,16,0,0,0-1,15.7c9.06,18.53,27.73,37.06,46.46,46.11a16,16,0,0,0,15.75-1.14,8.44,8.44,0,0,0,.74-.56L168.89,152l47,21.05h0s.08,0,.11,0A40.21,40.21,0,0,1,176,208Z\"/>", "lock-simple": "<path d=\"M208,80H176V56a48,48,0,0,0-96,0V80H48A16,16,0,0,0,32,96V208a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V96A16,16,0,0,0,208,80ZM96,56a32,32,0,0,1,64,0V80H96ZM208,208H48V96H208V208Z\"/>", "eye": "<path d=\"M247.31,124.76c-.35-.79-8.82-19.58-27.65-38.41C194.57,61.26,162.88,48,128,48S61.43,61.26,36.34,86.35C17.51,105.18,9,124,8.69,124.76a8,8,0,0,0,0,6.5c.35.79,8.82,19.57,27.65,38.4C61.43,194.74,93.12,208,128,208s66.57-13.26,91.66-38.34c18.83-18.83,27.3-37.61,27.65-38.4A8,8,0,0,0,247.31,124.76ZM128,192c-30.78,0-57.67-11.19-79.93-33.25A133.47,133.47,0,0,1,25,128,133.33,133.33,0,0,1,48.07,97.25C70.33,75.19,97.22,64,128,64s57.67,11.19,79.93,33.25A133.46,133.46,0,0,1,231.05,128C223.84,141.46,192.43,192,128,192Zm0-112a48,48,0,1,0,48,48A48.05,48.05,0,0,0,128,80Zm0,80a32,32,0,1,1,32-32A32,32,0,0,1,128,160Z\"/>", "eye-slash": "<path d=\"M53.92,34.62A8,8,0,1,0,42.08,45.38L61.32,66.55C25,88.84,9.38,123.2,8.69,124.76a8,8,0,0,0,0,6.5c.35.79,8.82,19.57,27.65,38.4C61.43,194.74,93.12,208,128,208a127.11,127.11,0,0,0,52.07-10.83l22,24.21a8,8,0,1,0,11.84-10.76Zm47.33,75.84,41.67,45.85a32,32,0,0,1-41.67-45.85ZM128,192c-30.78,0-57.67-11.19-79.93-33.25A133.16,133.16,0,0,1,25,128c4.69-8.79,19.66-33.39,47.35-49.38l18,19.75a48,48,0,0,0,63.66,70l14.73,16.2A112,112,0,0,1,128,192Zm6-95.43a8,8,0,0,1,3-15.72,48.16,48.16,0,0,1,38.77,42.64,8,8,0,0,1-7.22,8.71,6.39,6.39,0,0,1-.75,0,8,8,0,0,1-8-7.26A32.09,32.09,0,0,0,134,96.57Zm113.28,34.69c-.42.94-10.55,23.37-33.36,43.8a8,8,0,1,1-10.67-11.92A132.77,132.77,0,0,0,231.05,128a133.15,133.15,0,0,0-23.12-30.77C185.67,75.19,158.78,64,128,64a118.37,118.37,0,0,0-19.36,1.57A8,8,0,1,1,106,49.79,134,134,0,0,1,128,48c34.88,0,66.57,13.26,91.66,38.35,18.83,18.83,27.3,37.62,27.65,38.41A8,8,0,0,1,247.31,131.26Z\"/>", "warning": "<path d=\"M236.8,188.09,149.35,36.22h0a24.76,24.76,0,0,0-42.7,0L19.2,188.09a23.51,23.51,0,0,0,0,23.72A24.35,24.35,0,0,0,40.55,224h174.9a24.35,24.35,0,0,0,21.33-12.19A23.51,23.51,0,0,0,236.8,188.09ZM222.93,203.8a8.5,8.5,0,0,1-7.48,4.2H40.55a8.5,8.5,0,0,1-7.48-4.2,7.59,7.59,0,0,1,0-7.72L120.52,44.21a8.75,8.75,0,0,1,15,0l87.45,151.87A7.59,7.59,0,0,1,222.93,203.8ZM120,144V104a8,8,0,0,1,16,0v40a8,8,0,0,1-16,0Zm20,36a12,12,0,1,1-12-12A12,12,0,0,1,140,180Z\"/>", "info": "<path d=\"M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216Zm16-40a8,8,0,0,1-8,8,16,16,0,0,1-16-16V128a8,8,0,0,1,0-16,16,16,0,0,1,16,16v40A8,8,0,0,1,144,176ZM112,84a12,12,0,1,1,12,12A12,12,0,0,1,112,84Z\"/>", "clock-counter-clockwise": "<path d=\"M136,80v43.47l36.12,21.67a8,8,0,0,1-8.24,13.72l-40-24A8,8,0,0,1,120,128V80a8,8,0,0,1,16,0Zm-8-48A95.44,95.44,0,0,0,60.08,60.15C52.81,67.51,46.35,74.59,40,82V64a8,8,0,0,0-16,0v40a8,8,0,0,0,8,8H72a8,8,0,0,0,0-16H49c7.15-8.42,14.27-16.35,22.39-24.57a80,80,0,1,1,1.66,114.75,8,8,0,1,0-11,11.64A96,96,0,1,0,128,32Z\"/>", "arrow-u-up-left": "<path d=\"M232,144a64.07,64.07,0,0,1-64,64H80a8,8,0,0,1,0-16h88a48,48,0,0,0,0-96H51.31l34.35,34.34a8,8,0,0,1-11.32,11.32l-48-48a8,8,0,0,1,0-11.32l48-48A8,8,0,0,1,85.66,45.66L51.31,80H168A64.07,64.07,0,0,1,232,144Z\"/>", "user-plus": "<path d=\"M256,136a8,8,0,0,1-8,8H232v16a8,8,0,0,1-16,0V144H200a8,8,0,0,1,0-16h16V112a8,8,0,0,1,16,0v16h16A8,8,0,0,1,256,136Zm-57.87,58.85a8,8,0,0,1-12.26,10.3C165.75,181.19,138.09,168,108,168s-57.75,13.19-77.87,37.15a8,8,0,0,1-12.25-10.3c14.94-17.78,33.52-30.41,54.17-37.17a68,68,0,1,1,71.9,0C164.6,164.44,183.18,177.07,198.13,194.85ZM108,152a52,52,0,1,0-52-52A52.06,52.06,0,0,0,108,152Z\"/>", "coffee": "<path d=\"M80,56V24a8,8,0,0,1,16,0V56a8,8,0,0,1-16,0Zm40,8a8,8,0,0,0,8-8V24a8,8,0,0,0-16,0V56A8,8,0,0,0,120,64Zm32,0a8,8,0,0,0,8-8V24a8,8,0,0,0-16,0V56A8,8,0,0,0,152,64Zm96,56v8a40,40,0,0,1-37.51,39.91,96.59,96.59,0,0,1-27,40.09H208a8,8,0,0,1,0,16H32a8,8,0,0,1,0-16H56.54A96.3,96.3,0,0,1,24,136V88a8,8,0,0,1,8-8H208A40,40,0,0,1,248,120ZM200,96H40v40a80.27,80.27,0,0,0,45.12,72h69.76A80.27,80.27,0,0,0,200,136Zm32,24a24,24,0,0,0-16-22.62V136a95.78,95.78,0,0,1-1.2,15A24,24,0,0,0,232,128Z\"/>", "storefront": "<path d=\"M232,96a7.89,7.89,0,0,0-.3-2.2L217.35,43.6A16.07,16.07,0,0,0,202,32H54A16.07,16.07,0,0,0,38.65,43.6L24.31,93.8A7.89,7.89,0,0,0,24,96h0v16a40,40,0,0,0,16,32v72a8,8,0,0,0,8,8H208a8,8,0,0,0,8-8V144a40,40,0,0,0,16-32V96ZM54,48H202l11.42,40H42.61Zm50,56h48v8a24,24,0,0,1-48,0Zm-16,0v8a24,24,0,0,1-35.12,21.26,7.88,7.88,0,0,0-1.82-1.06A24,24,0,0,1,40,112v-8ZM200,208H56V151.2a40.57,40.57,0,0,0,8,.8,40,40,0,0,0,32-16,40,40,0,0,0,64,0,40,40,0,0,0,32,16,40.57,40.57,0,0,0,8-.8Zm4.93-75.8a8.08,8.08,0,0,0-1.8,1.05A24,24,0,0,1,168,112v-8h48v8A24,24,0,0,1,204.93,132.2Z\"/>", "list-numbers": "<path d=\"M224,128a8,8,0,0,1-8,8H104a8,8,0,0,1,0-16H216A8,8,0,0,1,224,128ZM104,72H216a8,8,0,0,0,0-16H104a8,8,0,0,0,0,16ZM216,184H104a8,8,0,0,0,0,16H216a8,8,0,0,0,0-16ZM43.58,55.16,48,52.94V104a8,8,0,0,0,16,0V40a8,8,0,0,0-11.58-7.16l-16,8a8,8,0,0,0,7.16,14.32ZM79.77,156.72a23.73,23.73,0,0,0-9.6-15.95,24.86,24.86,0,0,0-34.11,4.7,23.63,23.63,0,0,0-3.57,6.46,8,8,0,1,0,15,5.47,7.84,7.84,0,0,1,1.18-2.13,8.76,8.76,0,0,1,12-1.59A7.91,7.91,0,0,1,63.93,159a7.64,7.64,0,0,1-1.57,5.78,1,1,0,0,0-.08.11L33.59,203.21A8,8,0,0,0,40,216H72a8,8,0,0,0,0-16H56l19.08-25.53A23.47,23.47,0,0,0,79.77,156.72Z\"/>", "sign-out": "<path d=\"M120,216a8,8,0,0,1-8,8H48a8,8,0,0,1-8-8V40a8,8,0,0,1,8-8h64a8,8,0,0,1,0,16H56V208h56A8,8,0,0,1,120,216Zm109.66-93.66-40-40a8,8,0,0,0-11.32,11.32L204.69,120H112a8,8,0,0,0,0,16h92.69l-26.35,26.34a8,8,0,0,0,11.32,11.32l40-40A8,8,0,0,0,229.66,122.34Z\"/>", "map-pin": "<path d=\"M128,64a40,40,0,1,0,40,40A40,40,0,0,0,128,64Zm0,64a24,24,0,1,1,24-24A24,24,0,0,1,128,128Zm0-112a88.1,88.1,0,0,0-88,88c0,31.4,14.51,64.68,42,96.25a254.19,254.19,0,0,0,41.45,38.3,8,8,0,0,0,9.18,0A254.19,254.19,0,0,0,174,200.25c27.45-31.57,42-64.85,42-96.25A88.1,88.1,0,0,0,128,16Zm0,206c-16.53-13-72-60.75-72-118a72,72,0,0,1,144,0C200,161.23,144.53,209,128,222Z\"/>", "whatsapp-logo": "<path d=\"M187.58,144.84l-32-16a8,8,0,0,0-8,.5l-14.69,9.8a40.55,40.55,0,0,1-16-16l9.8-14.69a8,8,0,0,0,.5-8l-16-32A8,8,0,0,0,104,64a40,40,0,0,0-40,40,88.1,88.1,0,0,0,88,88,40,40,0,0,0,40-40A8,8,0,0,0,187.58,144.84ZM152,176a72.08,72.08,0,0,1-72-72A24,24,0,0,1,99.29,80.46l11.48,23L101,118a8,8,0,0,0-.73,7.51,56.47,56.47,0,0,0,30.15,30.15A8,8,0,0,0,138,155l14.61-9.74,23,11.48A24,24,0,0,1,152,176ZM128,24A104,104,0,0,0,36.18,176.88L24.83,210.93a16,16,0,0,0,20.24,20.24l34.05-11.35A104,104,0,1,0,128,24Zm0,192a87.87,87.87,0,0,1-44.06-11.81,8,8,0,0,0-6.54-.67L40,216,52.47,178.6a8,8,0,0,0-.66-6.54A88,88,0,1,1,128,216Z\"/>", "instagram-logo": "<path d=\"M128,80a48,48,0,1,0,48,48A48.05,48.05,0,0,0,128,80Zm0,80a32,32,0,1,1,32-32A32,32,0,0,1,128,160ZM176,24H80A56.06,56.06,0,0,0,24,80v96a56.06,56.06,0,0,0,56,56h96a56.06,56.06,0,0,0,56-56V80A56.06,56.06,0,0,0,176,24Zm40,152a40,40,0,0,1-40,40H80a40,40,0,0,1-40-40V80A40,40,0,0,1,80,40h96a40,40,0,0,1,40,40ZM192,76a12,12,0,1,1-12-12A12,12,0,0,1,192,76Z\"/>", "navigation-arrow": "<path d=\"M237.33,106.21,61.41,41l-.16-.05A16,16,0,0,0,40.9,61.25a1,1,0,0,0,.05.16l65.26,175.92A15.77,15.77,0,0,0,121.28,248h.3a15.77,15.77,0,0,0,15-11.29l.06-.2,21.84-78,78-21.84.2-.06a16,16,0,0,0,.62-30.38ZM149.84,144.3a8,8,0,0,0-5.54,5.54L121.3,232l-.06-.17L56,56l175.82,65.22.16.06Z\"/>", "image": "<path d=\"M216,40H40A16,16,0,0,0,24,56V200a16,16,0,0,0,16,16H216a16,16,0,0,0,16-16V56A16,16,0,0,0,216,40Zm0,16V158.75l-26.07-26.06a16,16,0,0,0-22.63,0l-20,20-44-44a16,16,0,0,0-22.62,0L40,149.37V56ZM40,172l52-52,80,80H40Zm176,28H194.63l-36-36,20-20L216,181.38V200ZM144,100a12,12,0,1,1,12,12A12,12,0,0,1,144,100Z\"/>", "package": "<path d=\"M223.68,66.15,135.68,18a15.88,15.88,0,0,0-15.36,0l-88,48.17a16,16,0,0,0-8.32,14v95.64a16,16,0,0,0,8.32,14l88,48.17a15.88,15.88,0,0,0,15.36,0l88-48.17a16,16,0,0,0,8.32-14V80.18A16,16,0,0,0,223.68,66.15ZM128,32l80.34,44-29.77,16.3-80.35-44ZM128,120,47.66,76l33.9-18.56,80.34,44ZM40,90l80,43.78v85.79L40,175.82Zm176,85.78h0l-80,43.79V133.82l32-17.51V152a8,8,0,0,0,16,0V107.55L216,90v85.77Z\"/>", "tag": "<path d=\"M243.31,136,144,36.69A15.86,15.86,0,0,0,132.69,32H40a8,8,0,0,0-8,8v92.69A15.86,15.86,0,0,0,36.69,144L136,243.31a16,16,0,0,0,22.63,0l84.68-84.68a16,16,0,0,0,0-22.63Zm-96,96L48,132.69V48h84.69L232,147.31ZM96,84A12,12,0,1,1,84,72,12,12,0,0,1,96,84Z\"/>"};
function cx(){ return Array.prototype.filter.call(arguments, Boolean).join(' '); }
function rest(p, omit){ var o = {}; for (var k in p) if (omit.indexOf(k) < 0) o[k] = p[k]; return o; }

function Icon(p){
  var size = p.size || 20;
  return h('svg', { className: cx('dw-icon', p.mirror && 'dw-mirror', p.className), width: size, height: size, viewBox: '0 0 256 256', fill: 'currentColor',
    'aria-hidden': p.label ? undefined : 'true', role: p.label ? 'img' : undefined, 'aria-label': p.label,
    dangerouslySetInnerHTML: { __html: ICONS[p.name] || '' } });
}

function Button(p){
  var variant = p.variant || 'primary', size = p.size || 'md';
  return h('button', Object.assign({ type: 'button' }, rest(p, ['variant','size','icon','block','loading','children','className']), {
      className: cx('dw-btn', 'dw-btn-' + variant, 'dw-btn-' + size, p.block && 'dw-btn-block', p.loading && 'is-loading', p.className),
      'aria-busy': p.loading ? 'true' : undefined, disabled: p.disabled || p.loading }),
    p.loading ? h('span', { className: 'dw-spinner', 'aria-hidden': 'true' }) : (p.icon ? h(Icon, { name: p.icon, size: size === 'lg' ? 24 : 20 }) : null),
    h('span', null, p.children));
}

function TextField(p){
  var st = useState(false), shown = st[0], setShown = st[1];
  var id = p.id || ('f-' + (p.label || 'x').length + '-' + (p.placeholder || '').length);
  var type = p.type === 'password' && shown ? 'text' : (p.type || 'text');
  return h('div', { className: cx('dw-field', p.error && 'has-error') },
    p.label && h('label', { className: 'dw-field-label', htmlFor: id }, p.label),
    h('div', { className: 'dw-field-box' },
      p.prefix && h('span', { className: 'dw-field-prefix', dir: 'ltr' }, p.prefix),
      h('input', { id: id, className: 'dw-field-input', type: type, defaultValue: p.value, placeholder: p.placeholder, dir: p.dir, inputMode: p.inputMode,
        'aria-invalid': p.error ? 'true' : undefined, 'aria-describedby': (p.error || p.hint) ? id + '-d' : undefined }),
      p.type === 'password' && h('button', { type: 'button', className: 'dw-field-toggle', onClick: function(){ setShown(!shown); },
        'aria-label': shown ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور' }, h(Icon, { name: shown ? 'eye-slash' : 'eye' }))),
    (p.error || p.hint) && h('p', { id: id + '-d', className: p.error ? 'dw-field-error' : 'dw-field-hint' },
      p.error && h(Icon, { name: 'warning', size: 16 }), p.error || p.hint));
}

function SegmentedControl(p){
  var st = useState(p.value != null ? p.value : p.options[0].value), v = st[0], set = st[1];
  return h('div', { className: 'dw-seg', role: 'radiogroup', 'aria-label': p.label },
    p.options.map(function(o){
      var on = o.value === v;
      return h('button', { key: o.value, type: 'button', role: 'radio', 'aria-checked': on ? 'true' : 'false',
        className: cx('dw-seg-opt', on && 'is-on'), onClick: function(){ set(o.value); p.onChange && p.onChange(o.value); } },
        o.icon && h(Icon, { name: o.icon, size: 18 }), o.label);
    }));
}

function ServiceChip(p){
  var st = useState(!!p.selected), on = st[0], set = st[1];
  return h('button', { type: 'button', role: 'checkbox', 'aria-checked': on ? 'true' : 'false', className: cx('dw-svc', on && 'is-on'),
      onClick: function(){ set(!on); p.onToggle && p.onToggle(!on); } },
    h('span', { className: 'dw-svc-check', 'aria-hidden': 'true' }, on ? h(Icon, { name: 'check', size: 16 }) : null),
    h('span', { className: 'dw-svc-main' }, h('span', { className: 'dw-svc-name' }, p.name),
      h('span', { className: 'dw-svc-meta' }, h(Icon, { name: 'clock', size: 16 }), p.minutes + ' دقيقة')),
    h('span', { className: 'dw-svc-price' }, h('bdi', null, p.price), ' ', p.currency || 'ر.س'));
}

var STATUS = {
  waiting:  ['بانتظار الدور', 'neutral', 'hourglass-medium'],
  called:   ['اقترب دورك', 'warning', 'bell-ringing'],
  in_service: ['في الخدمة', 'primary', 'scissors'],
  done:     ['تمت الخدمة', 'success', 'check-circle'],
  cancelled:['ملغى', 'danger', 'x-circle'],
  no_show:  ['لم يحضر', 'danger', 'x-circle'],
  postponed:['مؤجَّل دورًا', 'warning', 'arrow-u-up-left'],
  offered:  ['عرض مؤقت', 'steel', 'hourglass-medium'],
  requested:['ساعة محددة', 'steel', 'clock'],
  walk_in:  ['حاضر', 'neutral', 'user'],
  pay_awaiting: ['بانتظار تأكيد الدفع', 'warning', 'coins'],
  pay_confirmed:['تم تأكيد الدفع', 'success', 'coins']
};
function StatusBadge(p){
  var s = STATUS[p.status] || [p.status, 'neutral', null];
  return h('span', { className: cx('dw-badge', 'dw-tone-' + (p.tone || s[1]), p.size === 'sm' && 'dw-badge-sm') },
    s[2] && h(Icon, { name: s[2], size: p.size === 'sm' ? 14 : 16 }), p.label || s[0]);
}

function initials(name){ var w = String(name || '').trim().split(/\s+/); return (w[0] || '').charAt(0) + (w[1] ? w[1].charAt(0) : ''); }
function Avatar(p){
  var size = p.size || 40;
  return h('span', { className: cx('dw-avatar', p.tone && 'dw-avatar-' + p.tone), style: { width: size, height: size, fontSize: Math.round(size * 0.38) }, 'aria-hidden': 'true' }, initials(p.name));
}

function BarberOption(p){
  return h('button', { type: 'button', role: 'radio', 'aria-checked': p.selected ? 'true' : 'false', disabled: p.unavailable,
      className: cx('dw-barber', p.selected && 'is-on', p.unavailable && 'is-off') },
    p.fastest ? h('span', { className: 'dw-barber-auto', 'aria-hidden': 'true' }, h(Icon, { name: 'users-three', size: 22 })) : h(Avatar, { name: p.name, size: 44 }),
    h('span', { className: 'dw-barber-main' },
      h('span', { className: 'dw-barber-name' }, p.fastest ? 'الأسرع' : p.name),
      h('span', { className: 'dw-barber-meta' }, p.unavailable ? (p.reason || 'غير متاح اليوم') : (p.fastest ? 'يختار النظام من يبدأ خدمتك أولًا' : (p.note || 'أقرب وقت لبدء خدمتك')))),
    !p.unavailable && h('span', { className: 'dw-barber-time' }, h('bdi', { className: 'dw-num' }, p.nextAt), h('span', { className: 'dw-barber-wait' }, p.wait)));
}

function EtaCard(p){
  var changed = p.originalEta && p.originalEta !== p.eta;
  return h('section', { className: cx('dw-eta', p.live === false && 'is-stale'), 'aria-label': 'موعدك المتوقع' },
    h('div', { className: 'dw-eta-top' }, h(StatusBadge, { status: p.status || 'waiting' }),
      p.kind === 'requested' && h(StatusBadge, { status: 'requested', size: 'sm' })),
    h('p', { className: 'dw-eta-label' }, p.status === 'in_service' ? 'بدأت خدمتك' : 'يُتوقع أن تبدأ خدمتك'),
    h('p', { className: 'dw-eta-time' }, h('bdi', null, p.eta), h('span', { className: 'dw-eta-ampm' }, p.ampm || 'ص')),
    changed && h('p', { className: 'dw-eta-was' }, 'كان متوقعًا ', h('bdi', null, p.originalEta), p.reason ? ' — ' + p.reason : ''),
    h('div', { className: 'dw-eta-who' }, h(Avatar, { name: p.barber, size: 36 }),
      h('div', null, h('p', { className: 'dw-eta-barber' }, p.barber), h('p', { className: 'dw-eta-svc' }, p.services))),
    h('p', { className: 'dw-eta-foot' }, h(Icon, { name: p.live === false ? 'wifi-slash' : 'clock-counter-clockwise', size: 16 }),
      p.live === false ? 'الوقت تقديري — لم يصلنا تحديث من الصالون منذ ' + (p.staleFor || 'دقائق') : 'آخر تحديث ' + (p.updated || 'الآن')));
}

function QueueItem(p){
  return h('li', { className: cx('dw-q', 'dw-q-' + (p.status || 'waiting')) },
    h('span', { className: 'dw-q-pos dw-num' }, p.position),
    h('div', { className: 'dw-q-main' },
      h('div', { className: 'dw-q-head' }, h('span', { className: 'dw-q-name' }, p.name),
        p.kind === 'requested' && h(StatusBadge, { status: 'requested', size: 'sm', label: 'ساعة ' + p.requestedAt }),
        p.walkIn && h(StatusBadge, { status: 'walk_in', size: 'sm' }),
        p.status && p.status !== 'waiting' && h(StatusBadge, { status: p.status, size: 'sm' })),
      h('p', { className: 'dw-q-svc' }, p.services)),
    h('div', { className: 'dw-q-time' }, h('bdi', { className: 'dw-num' }, p.eta), p.duration && h('span', null, p.duration)),
    p.action && h('div', { className: 'dw-q-act' }, p.action));
}

function CurrentServiceCard(p){
  var pct = Math.min(100, Math.round(100 * p.elapsed / p.estimate)), over = p.elapsed > p.estimate;
  return h('section', { className: cx('dw-cur', over && 'is-over'), 'aria-label': 'الخدمة الجارية' },
    h('div', { className: 'dw-cur-head' }, h(StatusBadge, { status: 'in_service' }), h('span', { className: 'dw-cur-since' }, 'بدأت ', h('bdi', null, p.startedAt))),
    h('p', { className: 'dw-cur-name' }, p.customer),
    h('p', { className: 'dw-cur-svc' }, p.services, ' ', h('button', { type: 'button', className: 'dw-link' }, 'تعديل الخدمة')),
    h('div', { className: 'dw-cur-timer' },
      h('span', { className: 'dw-cur-elapsed dw-num' }, p.elapsed, h('small', null, ' د')),
      h('span', { className: 'dw-cur-of' }, 'من ', h('bdi', null, p.estimate), ' د مقدّرة')),
    h('div', { className: 'dw-meter', role: 'progressbar', 'aria-valuemin': 0, 'aria-valuemax': p.estimate, 'aria-valuenow': p.elapsed },
      h('span', { style: { width: pct + '%' } })),
    over && h('p', { className: 'dw-cur-warn' }, h(Icon, { name: 'warning', size: 16 }), 'تجاوزت الخدمة مدتها المقدرة — لا تنسَ الضغط على «إنهاء»'),
    h(Button, { variant: 'primary', size: 'lg', block: true, icon: 'check-circle' }, 'إنهاء الخدمة'));
}

function OfferCard(p){
  var pct = Math.round(100 * p.secondsLeft / (p.total || 120));
  var mm = Math.floor(p.secondsLeft / 60), ss = ('0' + (p.secondsLeft % 60)).slice(-2);
  return h('section', { className: 'dw-offer', 'aria-label': 'أقرب وقت متاح' },
    h('p', { className: 'dw-offer-q' }, 'الساعة ', h('bdi', null, p.requested), ' غير متاحة. أقرب وقت متاح:'),
    h('p', { className: 'dw-offer-time' }, h('bdi', null, p.offered), h('span', null, ' عند ', p.barber)),
    h('div', { className: 'dw-meter dw-meter-steel', 'aria-hidden': 'true' }, h('span', { style: { width: pct + '%' } })),
    h('p', { className: 'dw-offer-hold' }, 'محجوز لك لمدة ', h('bdi', { className: 'dw-num' }, mm + ':' + ss)),
    h('div', { className: 'dw-row' }, h(Button, { variant: 'primary', block: true }, 'احجز هذا الوقت'), h(Button, { variant: 'secondary', block: true }, 'لا، شكرًا')));
}

function ImpactList(p){
  return h('section', { className: 'dw-impact', 'aria-label': 'أثر التغيير' },
    h('p', { className: 'dw-impact-title' }, p.title || 'سيتأثر بهذا التغيير:'),
    h('ul', null, p.items.map(function(it, i){
      return h('li', { key: i, className: cx(it.pastClosing && 'is-closing', it.notify && 'is-notify') },
        h('span', { className: 'dw-impact-name' }, it.name),
        h('span', { className: 'dw-impact-times' }, h('bdi', null, it.from), h(Icon, { name: 'caret-left', size: 14, mirror: false }), h('bdi', null, it.to)),
        h('span', { className: 'dw-impact-delta' }, it.pastClosing ? 'بعد الإغلاق' : '+' + it.delta + ' د'));
    })),
    p.note && h('p', { className: 'dw-impact-note' }, h(Icon, { name: 'bell-ringing', size: 16 }), p.note));
}

var BANNER_ICON = { info: 'info', success: 'check-circle', warning: 'warning', danger: 'x-circle' };
function Banner(p){
  var tone = p.tone || 'info';
  return h('div', { className: cx('dw-banner', 'dw-banner-' + tone), role: tone === 'danger' ? 'alert' : 'status' },
    h(Icon, { name: BANNER_ICON[tone], size: 22 }),
    h('div', { className: 'dw-banner-body' }, p.title && h('p', { className: 'dw-banner-title' }, p.title), p.children && h('p', null, p.children)),
    p.action && h('div', { className: 'dw-banner-act' }, p.action));
}

function ConnectionBar(p){
  var s = p.state || 'online';
  var txt = s === 'online' ? 'متصل' : s === 'syncing' ? 'جارٍ مزامنة ' + (p.pending || 0) + ' إجراء' : 'غير متصل منذ ' + (p.since || '') + (p.pending ? ' — ' + p.pending + ' إجراء بانتظار المزامنة' : '');
  return h('div', { className: cx('dw-conn', 'dw-conn-' + s), role: 'status' },
    h(Icon, { name: s === 'offline' ? 'wifi-slash' : 'wifi-high', size: 18 }), h('span', null, txt),
    s === 'offline' && h('span', { className: 'dw-conn-note' }, 'إضافة زبون حاضر متوقفة'));
}

function Switch(p){
  var st = useState(!!p.checked), on = st[0], set = st[1];
  var id = p.id || 'sw-' + String(p.label).length;
  return h('div', { className: 'dw-setting' },
    h('div', { className: 'dw-setting-text' }, h('label', { htmlFor: id, className: 'dw-setting-label' }, p.label), p.description && h('p', { className: 'dw-setting-desc' }, p.description)),
    h('button', { id: id, type: 'button', role: 'switch', 'aria-checked': on ? 'true' : 'false', className: cx('dw-switch', on && 'is-on'), onClick: function(){ set(!on); } },
      h('span', { className: 'dw-switch-thumb' })));
}

function StatTile(p){
  var max = Math.max.apply(null, (p.series || [1]).concat([1]));
  return h('section', { className: 'dw-stat', 'aria-label': p.label },
    h('p', { className: 'dw-stat-label' }, p.label),
    h('p', { className: 'dw-stat-value' }, h('bdi', { className: 'dw-num' }, p.value), p.unit && h('span', null, ' ' + p.unit)),
    p.delta && h('p', { className: cx('dw-stat-delta', p.deltaTone && 'dw-text-' + p.deltaTone) }, p.delta),
    p.series && h('div', { className: 'dw-bars', 'aria-hidden': 'true' }, p.series.map(function(v, i){
      return h('span', { key: i, className: i === p.series.length - 1 ? 'is-last' : '', style: { height: Math.max(6, Math.round(100 * v / max)) + '%' } });
    })));
}

function BottomNav(p){
  return h('nav', { className: 'dw-nav', 'aria-label': 'التنقل الرئيسي' }, p.items.map(function(it, i){
    var on = i === (p.active || 0);
    return h('a', { key: i, href: '#', className: cx('dw-nav-item', on && 'is-on'), 'aria-current': on ? 'page' : undefined, onClick: function(e){ e.preventDefault(); } },
      h('span', { className: 'dw-nav-icon' }, h(Icon, { name: it.icon, size: 24 }), it.badge ? h('span', { className: 'dw-nav-badge dw-num' }, it.badge) : null), h('span', null, it.label));
  }));
}

function EmptyState(p){
  return h('section', { className: 'dw-empty' },
    h('span', { className: 'dw-empty-icon', 'aria-hidden': 'true' }, h(Icon, { name: p.icon || 'coffee', size: 32 })),
    h('p', { className: 'dw-empty-title' }, p.title), p.body && h('p', { className: 'dw-empty-body' }, p.body), p.action);
}

function CatalogItem(p){
  return h('article', { className: cx('dw-cat', p.kind === 'product' && 'dw-cat-product') },
    h('div', { className: 'dw-cat-img', 'aria-hidden': p.image ? undefined : 'true' },
      p.image ? h('img', { src: p.image, alt: p.name }) : h(Icon, { name: p.kind === 'product' ? 'package' : 'scissors', size: 28 })),
    h('div', { className: 'dw-cat-main' },
      h('div', { className: 'dw-cat-head' }, h('h3', { className: 'dw-cat-name' }, p.name),
        h('span', { className: 'dw-cat-price' }, h('bdi', { className: 'dw-num' }, p.price), ' ', p.currency || 'ر.س')),
      p.description && h('p', { className: 'dw-cat-desc' }, p.description),
      p.features && h('ul', { className: 'dw-cat-feats' }, p.features.map(function(f, i){ return h('li', { key: i }, h(Icon, { name: 'check', size: 14 }), f); })),
      h('p', { className: 'dw-cat-meta' }, p.kind === 'product' ? h(R.Fragment, null, h(Icon, { name: 'tag', size: 14 }), 'متوفر في الصالون')
        : h(R.Fragment, null, h(Icon, { name: 'clock', size: 14 }), 'نحو ' + p.minutes + ' دقيقة'))));
}

function HoursList(p){
  return h('section', { className: 'dw-hours', 'aria-label': 'ساعات العمل' },
    h('div', { className: 'dw-hours-head' }, h(Icon, { name: 'clock', size: 20 }), h('span', null, 'ساعات العمل'),
      p.openNow != null && h(StatusBadge, { status: 'x', tone: p.openNow ? 'success' : 'neutral', size: 'sm', label: p.openNow ? 'مفتوح الآن' : 'مغلق الآن' })),
    h('dl', null, p.days.map(function(d, i){
      return h('div', { key: i, className: cx('dw-hours-row', d.today && 'is-today') }, h('dt', null, d.day),
        h('dd', null, d.closed ? 'مغلق' : h('bdi', { className: 'dw-num' }, d.from + ' – ' + d.to)));
    })));
}

function ContactBar(p){
  var items = [];
  if (p.phone) items.push(['phone', 'اتصال', p.phone]);
  if (p.whatsapp) items.push(['whatsapp-logo', 'واتساب', p.whatsapp]);
  if (p.maps) items.push(['navigation-arrow', 'الاتجاهات', p.address]);
  if (p.instagram) items.push(['instagram-logo', 'إنستغرام', p.instagram]);
  return h('div', { className: 'dw-contact' },
    p.address && h('p', { className: 'dw-contact-addr' }, h(Icon, { name: 'map-pin', size: 18 }), p.address),
    h('div', { className: 'dw-contact-row' }, items.map(function(it){
      return h('a', { key: it[0], href: '#', className: 'dw-contact-btn', onClick: function(e){ e.preventDefault(); } }, h(Icon, { name: it[0], size: 22 }), h('span', null, it[1]));
    })));
}

var api = { Icon: Icon, Button: Button, TextField: TextField, SegmentedControl: SegmentedControl, ServiceChip: ServiceChip, StatusBadge: StatusBadge,
  Avatar: Avatar, BarberOption: BarberOption, EtaCard: EtaCard, QueueItem: QueueItem, CurrentServiceCard: CurrentServiceCard, OfferCard: OfferCard,
  ImpactList: ImpactList, Banner: Banner, ConnectionBar: ConnectionBar, Switch: Switch, StatTile: StatTile, BottomNav: BottomNav, EmptyState: EmptyState,
  CatalogItem: CatalogItem, HoursList: HoursList, ContactBar: ContactBar };
window.Saloni = Object.assign(window.Saloni || {}, api);
})();
