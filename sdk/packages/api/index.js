const React = require("react");

function Stack(props = {}) {
  return React.createElement("Stack", props, props.children);
}

function Text(props = {}) {
  return React.createElement("Text", props, props.children);
}

function Button(props = {}) {
  return React.createElement("Button", props, props.children);
}

module.exports = {
  Stack,
  Text,
  Button,
};
