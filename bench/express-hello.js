const express = require('express');
const app = express();

app.get('*', (req, res) => {
  res.type('text/plain').send(`Hello, you requested ${req.path}`);
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`express listening on ${port}`));
