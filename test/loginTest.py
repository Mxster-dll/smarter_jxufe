import requests
import re
import json
from urllib.parse import urljoin


class JiangxiFinanceLogin:

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        })
        self.base_url = 'https://ssl.jxufe.edu.cn'

    def get_login_page(self):
        """获取登录页面，获取必要参数"""
        login_url = f'{self.base_url}/cas/login?service=http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess'
        response = self.session.get(login_url)

        # 提取 execution 参数
        execution = re.search(r'name="execution" value="([^"]+)"',
                              response.text)
        # 提取 fpVisitorId
        fp_visitor_id = re.search(r'name="fpVisitorId" value="([^"]+)"',
                                  response.text)

        return {
            'execution': execution.group(1) if execution else '',
            'fpVisitorId': fp_visitor_id.group(1) if fp_visitor_id else ''
        }

    def mfa_detect(self, username, password, params):
        """发送2FA检测请求"""
        detect_url = f'{self.base_url}/cas/mfa/detect'

        data = {
            'username': username,
            'password': password,
            'fpVisitorId': params['fpVisitorId']
        }

        response = self.session.post(detect_url, data=data)
        result = response.json()

        if result.get('code') == 0 and result.get('data', {}).get('need'):
            return result['data']['state']
        return None

    def get_qrcode_data(self, state):
        """获取二维码信息"""
        init_url = f'{self.base_url}/cas/mfa/initByType/qrcode'

        params = {'state': state}

        response = self.session.get(init_url, params=params)
        result = response.json()

        if result.get('code') == 0:
            return result.get('data', {})
        return None

    def get_qrcode_image(self, qrcode_data):
        """获取二维码图片"""
        # 从返回的数据中获取二维码图片URL
        qrcode_url = qrcode_data.get('qrCode', {}).get('scanQrcode')

        if not qrcode_url:
            # 如果直接返回的不是URL，可能需要拼接
            attest_server = qrcode_data.get('attestServerUrl', '')
            gid = qrcode_data.get('gid', '')

            if attest_server and gid:
                # 获取二维码的详细数据
                send_url = f'{attest_server}/api/guard/qrcode/send'
                send_data = {'gid': gid}

                response = self.session.post(send_url, json=send_data)
                result = response.json()

                if result.get('code') == 0:
                    qrcode_url = result.get('data', {}).get('scanQrcode')

        return qrcode_url

    def download_qrcode(self, qrcode_url, save_path='qrcode.png'):
        """下载二维码图片"""
        if not qrcode_url:
            print("未获取到二维码URL")
            return False

        # 确保URL完整
        if qrcode_url.startswith('/'):
            qrcode_url = f'{self.base_url}{qrcode_url}'

        response = self.session.get(qrcode_url)

        if response.status_code == 200:
            with open(save_path, 'wb') as f:
                f.write(response.content)
            print(f"二维码已保存到: {save_path}")
            return True
        else:
            print(f"下载失败，状态码: {response.status_code}")
            return False

    def login_and_get_qrcode(self, username, password):
        """完整流程：登录并获取二维码"""
        print("1. 获取登录页面参数...")
        params = self.get_login_page()

        print("2. 发送2FA检测请求...")
        state = self.mfa_detect(username, password, params)

        if not state:
            print("不需要2FA验证或检测失败")
            return None

        print(f"3. 获取2FA状态: {state}")
        qrcode_data = self.get_qrcode_data(state)

        if not qrcode_data:
            print("获取二维码数据失败")
            return None

        print("4. 获取二维码URL...")
        qrcode_url = self.get_qrcode_image(qrcode_data)

        if qrcode_url:
            print(f"5. 二维码URL: {qrcode_url}")
            self.download_qrcode(qrcode_url)
            return qrcode_url

        return None


# 使用示例
if __name__ == "__main__":
    login = JiangxiFinanceLogin()

    # 替换为你的账号密码
    username = "[REDACTED_EMAIL]"
    password = "[REDACTED_PWD]"

    qrcode_url = login.login_and_get_qrcode(username, password)
