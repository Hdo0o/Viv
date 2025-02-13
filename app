from flask import Flask, render_template_string, request, redirect, session
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime

app = Flask(__name__)
app.secret_key = 'viv_secret_123'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///viv_chat.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# النماذج
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True)
    password = db.Column(db.String(120))
    messages_sent = db.relationship('Message', foreign_keys='Message.sender_id', backref='sender', lazy=True)
    messages_received = db.relationship('Message', foreign_keys='Message.receiver_id', backref='receiver', lazy=True)

class Message(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    content = db.Column(db.Text)
    sender_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    receiver_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    timestamp = db.Column(db.DateTime, default=datetime.now)

# التصميم المخصص لـ Viv
VIV_STYLE = """
<style>
:root {
    --viv-primary: #6a1b9a;
    --viv-secondary: #9c27b0;
    --viv-bg: #f5e6ff;
    --viv-card: #ffffff;
}

body {
    background: var(--viv-bg);
    font-family: 'Segoe UI', sans-serif;
    margin: 0;
    height: 100vh;
}

.chat-container {
    max-width: 1000px;
    margin: 20px auto;
    display: grid;
    grid-template-columns: 250px 1fr;
    gap: 20px;
    height: 80vh;
}

.users-list {
    background: var(--viv-card);
    border-radius: 15px;
    padding: 15px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.chat-box {
    background: var(--viv-card);
    border-radius: 15px;
    padding: 20px;
    display: flex;
    flex-direction: column;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.message-input {
    margin-top: auto;
    display: flex;
    gap: 10px;
}

.message {
    padding: 10px 15px;
    margin: 8px 0;
    border-radius: 20px;
    max-width: 70%;
}

.received {
    background: #ede7f6;
    align-self: flex-start;
}

.sent {
    background: var(--viv-primary);
    color: white;
    align-self: flex-end;
}

.timestamp {
    font-size: 0.8em;
    color: #757575;
}
</style>
"""

# القوالب
login_template = VIV_STYLE + """
<div style="max-width:400px; margin:100px auto; text-align:center;">
    <div style="background:var(--viv-card); padding:40px; border-radius:20px; box-shadow:0 4px 12px rgba(0,0,0,0.15);">
        <h1 style="color:var(--viv-primary); margin:0 0 30px 0;">💬 VIV</h1>
        <form method="POST">
            <input type="text" name="username" placeholder="اسم المستخدم" 
                   style="width:100%; padding:12px; margin:10px 0; border:2px solid #e0e0e0; border-radius:10px;">
            <input type="password" name="password" placeholder="كلمة المرور" 
                   style="width:100%; padding:12px; margin:10px 0; border:2px solid #e0e0e0; border-radius:10px;">
            <button style="width:100%; padding:12px; background:var(--viv-primary); color:white; border:none; border-radius:10px; cursor:pointer;">
                دخول
            </button>
        </form>
        <p style="margin-top:20px;">ليس لديك حساب؟ <a href="/register" style="color:var(--viv-secondary);">سجل الآن</a></p>
    </div>
</div>
"""

chat_template = VIV_STYLE + """
<div style="padding:20px;">
    <header style="background:var(--viv-primary); color:white; padding:15px; border-radius:15px; margin-bottom:20px;">
        <h1 style="margin:0;">💬 VIV Chat - {{ current_user.username }}</h1>
        <a href="/logout" style="color:white; float:left; text-decoration:none;">تسجيل الخروج</a>
    </header>
    
    <div class="chat-container">
        <div class="users-list">
            <h3 style="margin-top:0;">المستخدمون</h3>
            {% for user in users %}
                {% if user.id != current_user.id %}
                <div style="padding:10px; margin:5px 0; cursor:pointer; background:{% if user.id == selected_user.id %} #f3e5f5{% endif %}; border-radius:10px;"
                     onclick="window.location='/chat/{{ user.id }}'">
                    👤 {{ user.username }}
                </div>
                {% endif %}
            {% endfor %}
        </div>
        
        <div class="chat-box">
            {% if selected_user %}
            <div style="flex-grow:1; overflow-y:auto; padding-right:10px;">
                {% for msg in messages %}
                <div class="message {% if msg.sender_id == current_user.id %}sent{% else %}received{% endif %}">
                    <div>{{ msg.content }}</div>
                    <div class="timestamp">{{ msg.timestamp.strftime('%H:%M') }}</div>
                </div>
                {% endfor %}
            </div>
            
            <form method="POST" class="message-input">
                <input type="hidden" name="receiver_id" value="{{ selected_user.id }}">
                <input type="text" name="content" placeholder="اكتب رسالة..." 
                       style="flex-grow:1; padding:12px; border:2px solid #e0e0e0; border-radius:25px;">
                <button style="background:var(--viv-primary); color:white; border:none; padding:12px 25px; border-radius:25px; cursor:pointer;">
                    إرسال
                </button>
            </form>
            {% else %}
            <div style="text-align:center; margin:auto; color:#666;">
                👈 اختر مستخدمًا لبدء الدردشة
            </div>
            {% endif %}
        </div>
    </div>
</div>
"""

register_template = VIV_STYLE + """
<div style="max-width:400px; margin:100px auto; text-align:center;">
    <div style="background:var(--viv-card); padding:40px; border-radius:20px; box-shadow:0 4px 12px rgba(0,0,0,0.15);">
        <h1 style="color:var(--viv-primary); margin:0 0 30px 0;">🎯 تسجيل جديد</h1>
        <form method="POST">
            <input type="text" name="username" placeholder="اسم مستخدم جديد" 
                   style="width:100%; padding:12px; margin:10px 0; border:2px solid #e0e0e0; border-radius:10px;">
            <input type="password" name="password" placeholder="كلمة المرور" 
                   style="width:100%; padding:12px; margin:10px 0; border:2px solid #e0e0e0; border-radius:10px;">
            <button style="width:100%; padding:12px; background:var(--viv-primary); color:white; border:none; border-radius:10px; cursor:pointer;">
                إنشاء حساب
            </button>
        </form>
        <p style="margin-top:20px;">لديك حساب؟ <a href="/login" style="color:var(--viv-secondary);">سجل الدخول</a></p>
    </div>
</div>
"""

# الروابط
@app.route('/')
def home():
    if 'user_id' in session:
        return redirect('/chat')
    return redirect('/login')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        user = User.query.filter_by(username=request.form['username']).first()
        if user and check_password_hash(user.password, request.form['password']):
            session['user_id'] = user.id
            return redirect('/chat')
    return render_template_string(login_template)

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        hashed_pw = generate_password_hash(request.form['password'])
        new_user = User(username=request.form['username'], password=hashed_pw)
        db.session.add(new_user)
        db.session.commit()
        return redirect('/login')
    return render_template_string(register_template)

@app.route('/logout')
def logout():
    session.pop('user_id', None)
    return redirect('/login')

@app.route('/chat')
@app.route('/chat/<int:user_id>')
def chat(user_id=None):
    if 'user_id' not in session:
        return redirect('/login')
    
    current_user = User.query.get(session['user_id'])
    users = User.query.filter(User.id != current_user.id).all()
    selected_user = User.query.get(user_id) if user_id else None
    messages = []
    
    if selected_user:
        messages = Message.query.filter(
            ((Message.sender_id == current_user.id) & (Message.receiver_id == selected_user.id)) |
            ((Message.sender_id == selected_user.id) & (Message.receiver_id == current_user.id))
        ).order_by(Message.timestamp).all()
    
    return render_template_string(chat_template, 
                                current_user=current_user,
                                users=users,
                                selected_user=selected_user,
                                messages=messages)

@app.route('/send', methods=['POST'])
def send_message():
    if 'user_id' in session:
        new_msg = Message(
            content=request.form['content'],
            sender_id=session['user_id'],
            receiver_id=request.form['receiver_id']
        )
        db.session.add(new_msg)
        db.session.commit()
    return redirect(f'/chat/{request.form["receiver_id"]}')

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    app.run(host='0.0.0.0', debug=True)  # يعمل على الشبكة المحلية
