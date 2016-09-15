var express = require('express');
var router = express.Router();

/* GET home page. */
router.get('/', function(req, res, next) {
  //res.render('index', { title: 'Express' });
  res.render('index', {
    title: 'pAnalytics',
    author: 'thelastpenguin',
    servers: [
        {
            name: 'server 1'
        },
        {
            name: 'server 2'
        },
        {
            name: 'server 3'
        }
    ]
  });
});

module.exports = router;
